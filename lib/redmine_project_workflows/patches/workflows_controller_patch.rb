# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowsControllerPatch
      def edit
        load_project_options
        if project_context?
          if @trackers.present? && @roles.present? && @statuses.any?
            workflows = WorkflowTransition.
              where(role_id: @roles.map(&:id), tracker_id: @trackers.map(&:id), project_id: selected_project_ids).
              preload(:old_status, :new_status)
            @workflows = {}
            @workflows['always'] = workflows.select { |workflow| !workflow.author && !workflow.assignee }
            @workflows['author'] = workflows.select(&:author)
            @workflows['assignee'] = workflows.select(&:assignee)
          end
        else
          super
          filter_global_workflows
        end
      end

      def update
        load_project_options
        if project_context?
          if @roles.present? && @trackers.present? && params[:transitions]
            transitions = params[:transitions].deep_dup
            transitions.each do |_old_status_id, transitions_by_new_status|
              transitions_by_new_status.each do |_new_status_id, transition_by_rule|
                transition_by_rule.reject! { |_rule, transition| transition == 'no_change' }
              end
            end
            selected_project_ids_for_update.each do |project_id|
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

      def permissions
        load_project_options
        if project_context?
          if @roles.present? && @trackers.present?
            @fields = (Tracker::CORE_FIELDS_ALL - @trackers.map(&:disabled_core_fields).reduce(:&)).map do |field|
              [field, l("field_" + field.sub(/_id$/, ''))]
            end
            @custom_fields = @trackers.map(&:custom_fields).flatten.uniq.sort
            @permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(
              @trackers,
              @roles,
              selected_project_ids
            )
            @statuses.each { |status| @permissions[status.id] ||= {} }
          end
        else
          super
          filter_global_permissions
        end
      end

      def update_permissions
        load_project_options
        if project_context?
          if @roles.present? && @trackers.present? && params[:permissions]
            permissions = normalize_permissions_params(params[:permissions].deep_dup)
            permissions.each_value do |rule_by_field|
              rule_by_field.reject! { |_field, rule| rule == 'no_change' }
            end
            selected_project_ids_for_update.each do |project_id|
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
        @source_project_id = params[:source_project_id].presence
        super
      end

      def duplicate
        load_project_options
        return super unless project_context?

        find_sources_and_targets
        source_project_id = params[:source_project_id].presence
        target_project_ids = Array.wrap(params[:target_project_ids]).reject(&:blank?)
        if params[:source_tracker_id].blank? || params[:source_role_id].blank? ||
          (@source_tracker.nil? && @source_role.nil?)
          @source_project_id = nil
          flash.now[:error] = l(:error_workflow_copy_source_project)
          render :copy
        elsif @target_trackers.blank? || @target_roles.blank? || target_project_ids.blank?
          flash.now[:error] = l(:error_workflow_copy_target)
          render :copy
        else
          @source_project_id = source_project_id
          resolved_target_project_ids = target_project_ids.map do |value|
            value == 'global' ? nil : value
          end
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
          flash[:notice] = l(:notice_successful_update)
          redirect_to copy_workflows_path(
            source_tracker_id: @source_tracker,
            source_role_id: @source_role,
            source_project_id: source_project_id
          )
        end
      end

      private

      def project_context?
        selected_projects.present?
      end

      def load_project_options
        @projects = Project.sorted
        project_param_values = params[:project_id].presence || params[:target_project_ids]
        project_ids = Array.wrap(project_param_values).reject(&:blank?).map(&:to_s)
        @all_selected = project_ids.delete('all').present?
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

        @selected_projects = Project.where(id: project_ids).sorted
        render_404 if @selected_projects.size != project_ids.size
        @projects_for_update = @selected_projects
        @project = @selected_projects.first if @selected_projects.one?
      end

      def selected_projects
        @projects_for_update || []
      end

      def selected_project_ids
        ids = selected_projects.map(&:id)
        ids << nil if @global_selected
        ids
      end

      def selected_project_ids_for_update
        ids = selected_projects.map(&:id)
        ids << nil if @global_selected
        ids
      end

      def selected_project_param_values
        return ['all'] if @all_selected

        values = selected_projects.map(&:id)
        values.unshift('global') if @global_selected
        values
      end

      def filter_global_workflows
        return unless @workflows.respond_to?(:transform_values)

        @workflows = @workflows.transform_values do |transitions|
          transitions.select { |transition| transition.project_id.nil? }
        end
      end

      def filter_global_permissions
        return unless @roles && @trackers

        @permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(
          @trackers,
          @roles,
          [nil]
        )
        @statuses.each { |status| @permissions[status.id] ||= {} }
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
    end
  end
end
