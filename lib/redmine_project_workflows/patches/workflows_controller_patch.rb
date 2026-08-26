# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowsControllerPatch
      # The parameters the plugin adds to core's workflow screens.
      PROJECT_PARAM_KEYS = %i[project_id target_project_ids source_project_id].freeze
      # The two non-numeric values the matrix selector accepts.
      PROJECT_KEYWORDS = %w[global all].freeze

      # Core's own edit runs without a project_id predicate, which would mix the
      # two populations (INV-4), so the plugin answers both cases itself.
      def edit
        return unless @trackers.present? && @roles.present? && @statuses.any?

        @project_workflow_scope_state = scope_state_for(ProjectWorkflowScope::TRANSITIONS)
        workflows = WorkflowTransition.
          where(role_id: @roles.map(&:id), tracker_id: @trackers.map(&:id), project_id: workflow_project_ids).
          preload(:old_status, :new_status)
        @workflows = {}
        @workflows['always'] = workflows.select { |workflow| !workflow.author && !workflow.assignee }
        @workflows['author'] = workflows.select(&:author)
        @workflows['assignee'] = workflows.select(&:assignee)
      end

      def update
        if project_context?
          if @roles.present? && @trackers.present? && params[:transitions]
            transitions = params[:transitions].deep_dup
            transitions.each do |_old_status_id, transitions_by_new_status|
              transitions_by_new_status.each do |_new_status_id, transition_by_rule|
                transition_by_rule.reject! { |_rule, transition| transition == 'no_change' }
              end
            end
            selected_project_ids.each do |project_id|
              RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
                project_id,
                @trackers,
                @roles,
                transitions
              )
            end
            flash[:notice] = l(:notice_successful_update)
          end
          redirect_to edit_workflows_path(project_id: selected_project_param_values, tracker_id: @trackers, role_id: @roles, used_statuses_only: params[:used_statuses_only])
        else
          super
        end
      end

      # See #edit: the same reason, for the field permissions matrix.
      def permissions
        return unless @roles.present? && @trackers.present?

        @project_workflow_scope_state = scope_state_for(ProjectWorkflowScope::PERMISSIONS)
        @fields = (Tracker::CORE_FIELDS_ALL - @trackers.map(&:disabled_core_fields).reduce(:&)).map do |field|
          [field, l("field_" + field.sub(/_id$/, ''))]
        end
        @custom_fields = @trackers.map(&:custom_fields).flatten.uniq.sort
        @permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(
          @trackers,
          @roles,
          workflow_project_ids
        )
        @statuses.each { |status| @permissions[status.id] ||= {} }
      end

      def update_permissions
        if project_context?
          if @roles.present? && @trackers.present? && params[:permissions]
            permissions = normalize_permissions_params(params[:permissions].deep_dup)
            permissions.each_value do |rule_by_field|
              rule_by_field.reject! { |_field, rule| rule == 'no_change' }
            end
            selected_project_ids.each do |project_id|
              RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
                project_id,
                @trackers,
                @roles,
                permissions
              )
            end
            flash[:notice] = l(:notice_successful_update)
          end
          redirect_to permissions_workflows_path(project_id: selected_project_param_values, tracker_id: @trackers, role_id: @roles, used_statuses_only: params[:used_statuses_only])
        else
          super
        end
      end

      def copy
        load_project_options
        if @invalid_project_ids.present?
          render_404
          return if performed?
        end

        @source_project_id = params[:source_project_id].presence
        super
      end

      def duplicate
        load_project_options
        return super unless project_context?

        find_sources_and_targets
        source_project_id = params[:source_project_id].presence
        resolved_target_project_ids, invalid_target_project_ids = validated_target_project_ids
        if params[:source_tracker_id].blank? || params[:source_role_id].blank? ||
          (@source_tracker.nil? && @source_role.nil?) ||
          (source_project_id.present? && !%w[any global].include?(source_project_id) &&
            (!source_project_id.to_s.match?(/\A\d+\z/) || !Project.exists?(source_project_id.to_i)))
          @source_project_id = nil
          flash.now[:error] = l(:error_workflow_copy_source_project)
          render :copy
        elsif invalid_target_project_ids.present?
          @source_project_id = source_project_id
          flash.now[:error] = l(:error_workflow_copy_target_project)
          render :copy
        elsif @target_trackers.blank? || @target_roles.blank? || resolved_target_project_ids.blank?
          flash.now[:error] = l(:error_workflow_copy_target)
          render :copy
        else
          @source_project_id = source_project_id
          ActiveRecord::Base.transaction do
            resolved_target_project_ids.each do |target_project_id|
              resolved_source_project_id =
                if source_project_id == 'any'
                  target_project_id
                elsif source_project_id.blank? || source_project_id == 'global'
                  nil
                else
                  source_project_id
                end
              WorkflowRule.copy_for_project(
                resolved_source_project_id,
                target_project_id,
                @source_tracker,
                @source_role,
                @target_trackers,
                @target_roles
              )
            end
            record_scopes_for_copy(resolved_target_project_ids)
          end
          flash[:notice] = l(:notice_successful_update)
          redirect_to copy_workflows_path(
            source_tracker_id: @source_tracker,
            source_role_id: @source_role,
            source_project_id: source_project_id
          )
        end
      end

      private

      # Whether this request is one the plugin has to handle itself.
      #
      # It reads the parameters, not the resolved project list: selecting only
      # the generic workflow resolves to an empty list of projects, and falling
      # through to core there makes `duplicate` copy generic to generic and
      # ignore the chosen source project entirely.
      def project_context?
        PROJECT_PARAM_KEYS.any? { |key| Array.wrap(params[key]).any?(&:present?) }
      end

      # Resolves the matrix selector. Values are 'global' (the generic
      # workflow), 'all', or project ids; anything else, and any id that does
      # not exist, is collected in @invalid_project_ids for the caller to
      # report. Nothing is rendered here: render_404 renders and returns false
      # rather than aborting, so the decision belongs where the action can
      # return straight after it.
      def load_project_options
        @projects = Project.sorted
        values = Array.wrap(params[:project_id]).reject(&:blank?).map(&:to_s).uniq
        @invalid_project_ids = values.reject { |value| project_id_value?(value) }
        project_ids = values - @invalid_project_ids

        @all_selected = project_ids.delete('all').present?
        # Global is selected when explicitly chosen, when 'all' is selected,
        # or when no project params are provided (default Redmine behavior).
        @global_selected = project_ids.delete('global').present? || project_ids.empty? || @all_selected

        if @all_selected
          @selected_projects = @projects
          @projects_for_update = @selected_projects
          return
        end

        if project_ids.blank?
          @selected_projects = []
          @projects_for_update = []
          return
        end

        @selected_projects = Project.where(id: project_ids).sorted.to_a
        @invalid_project_ids += project_ids - @selected_projects.map { |project| project.id.to_s }
        @projects_for_update = @selected_projects
        @project = @selected_projects.first if @selected_projects.one?
      end

      def project_id_value?(value)
        PROJECT_KEYWORDS.include?(value) || value.match?(/\A\d+\z/)
      end

      # The copy form's target selector, which is a different control from the
      # matrix selector above and accepts a different set of values: 'global'
      # or a project id, never 'all'. Returns the ids to write to -- nil for
      # the generic workflow -- and the values that were rejected, de-duplicated
      # and resolved in one query.
      def validated_target_project_ids
        values = Array.wrap(params[:target_project_ids]).reject(&:blank?).map(&:to_s).uniq
        invalid, valid = values.partition { |value| value != 'global' && !value.match?(/\A\d+\z/) }
        global = valid.delete('global').present?

        existing_ids = valid.empty? ? [] : Project.where(id: valid).pluck(:id)
        invalid += valid - existing_ids.map(&:to_s)

        resolved = existing_ids
        resolved.unshift(nil) if global
        [resolved, invalid]
      end

      def selected_projects
        @projects_for_update || []
      end

      def selected_project_ids
        ids = selected_projects.map(&:id)
        ids << nil if @global_selected
        ids
      end

      # A copy that lands in a project has to record the decision as well, or the
      # resolver ignores every row it just wrote (INV-3). copy_for_project moves
      # both kinds of rule, so both rule types are considered -- but a scope is
      # created only where the target now *has* rules, because an empty
      # transitions scope would stop every issue in the project from changing
      # status. A targeted pair that already carried rules without a scope gets
      # one too; that is a repair, not an over-reach, and it can only happen to
      # a pair the operator named.
      def record_scopes_for_copy(target_project_ids)
        RedmineProjectWorkflows::Services::ScopeWriter.ensure_scopes_for_copy(
          project_ids: target_project_ids.compact,
          tracker_ids: @target_trackers.map(&:id),
          role_ids: @target_roles.map(&:id),
          user: User.current
        )
      end

      # The state of the three INV-3 actions for the current selection, used by
      # the panel above the matrix. Built here rather than in the view so that
      # the view does no querying and the state can be asserted in a controller
      # spec.
      #
      # Only real projects have scopes: the generic workflow is the one thing
      # that cannot be inherited or emptied, so 'global' contributes nothing.
      def scope_state_for(rule_type)
        RedmineProjectWorkflows::Services::ScopeState.new(
          project_ids: selected_projects.map(&:id),
          tracker_ids: @trackers.map(&:id),
          role_ids: @roles.map(&:id),
          rule_type: rule_type
        )
      end

      # The population the matrix screens read. Without plugin parameters that
      # is the generic workflow alone, which is what core shows -- but stated
      # as an explicit predicate rather than left out (INV-4).
      def workflow_project_ids
        project_context? ? selected_project_ids : [nil]
      end

      def selected_project_param_values
        return ['all'] if @all_selected

        values = selected_projects.map(&:id)
        values.unshift('global') if @global_selected
        values
      end


      def normalize_permissions_params(permissions)
        permissions =
          if permissions.respond_to?(:to_unsafe_h)
            permissions.to_unsafe_h
          else
            permissions.to_h
          end
        return permissions if permissions.keys.all? { |key| key.to_s.match?(/\A\d+\z/) }

        normalized = {}
        permissions.each do |field, rules_by_status|
          next unless rules_by_status.respond_to?(:each)

          rules_by_status.each do |status_id, rule|
            normalized[status_id] ||= {}
            normalized[status_id][field] = rule
          end
        end
        normalized
      end

      def find_trackers_roles_and_statuses_for_edit
        find_roles
        find_trackers
        load_project_options
        if @invalid_project_ids.present?
          render_404
          return if performed?
        end

        find_statuses
      end

      def find_statuses
        @used_statuses_only = (params[:used_statuses_only] == '0' ? false : true)
        if @trackers && @used_statuses_only
          role_ids = Role.all.select(&:consider_workflow?).map(&:id)
          project_ids = selected_project_ids
          status_ids = WorkflowTransition.where(
            tracker_id: @trackers.map(&:id),
            role_id: role_ids,
            project_id: project_ids
          ).where(
            'old_status_id <> new_status_id'
          ).distinct.pluck(:old_status_id, :new_status_id).flatten.uniq
          @statuses = IssueStatus.where(id: status_ids).sorted.to_a.presence
        end
        @statuses ||= IssueStatus.sorted.to_a
      end
    end
  end
end
