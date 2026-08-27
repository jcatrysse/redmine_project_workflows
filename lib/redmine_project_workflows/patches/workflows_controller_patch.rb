# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowsControllerPatch
      # How a request names projects, and what it resolves to. See that module:
      # every method it adds is private, because this one is prepended to a
      # controller.
      include WorkflowsControllerProjectSelection

      # The summary page. Core's own body is the first two lines plus a count
      # with no project_id predicate at all, so every project's rules were
      # added into the generic totals -- a project that had taken over one
      # tracker made the generic workflow look like it had rules it does not
      # have (claude F01, INV-4). It is rewritten here rather than called
      # through super and corrected afterwards, because super's query is the
      # defect: running it and discarding the answer would still be a workflow
      # query with no project_id predicate.
      #
      # Core's two `@roles` / `@trackers` lines are byte-identical in Redmine
      # 5.1, 6.1 and 7.0.
      def index
        @roles = Role.sorted.select(&:consider_workflow?)
        @trackers = Tracker.sorted
        load_project_options
        return if invalid_project_selection?

        @project_workflow_selection = summary_selection_param_values
        @workflow_counts = WorkflowTransition
                           .where(project_id: workflow_project_ids)
                           .group(:tracker_id, :role_id).count
      end

      # Core's own edit runs without a project_id predicate, which would mix the
      # two populations (INV-4), so the plugin answers both cases itself.
      def edit
        return if invalid_project_selection?
        return unless @trackers.present? && @roles.present? && @statuses.any?

        @project_workflow_scope_state = scope_state_for(ProjectWorkflowScope::TRANSITIONS)
        workflows = WorkflowTransition
                    .where(role_id: @roles.map(&:id), tracker_id: @trackers.map(&:id), project_id: workflow_project_ids)
                    .preload(:old_status, :new_status)
        @workflows = {}
        @workflows['always'] = workflows.select { |workflow| !workflow.author && !workflow.assignee }
        @workflows['author'] = workflows.select(&:author)
        @workflows['assignee'] = workflows.select(&:assignee)
      end

      def update
        return if invalid_project_selection?

        if project_context?
          if @roles.present? && @trackers.present? && params[:transitions]
            transitions = strip_no_change(params[:transitions])
            result = RedmineProjectWorkflows::Services::MatrixSaveResult.none
            # One transaction over the whole selection, as #duplicate already
            # has: a failure half way through otherwise leaves some of the
            # selected workflows rewritten and the rest untouched.
            ActiveRecord::Base.transaction do
              result = selected_project_ids.sum(result) do |project_id|
                RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
                  project_id,
                  @trackers,
                  @roles,
                  transitions
                )
              end
            end
            report_matrix_save(result)
          end
          redirect_to edit_workflows_path(project_id: selected_project_param_values, tracker_id: @trackers,
                                          role_id: @roles, used_statuses_only: params[:used_statuses_only])
        else
          super
        end
      end

      # See #edit: the same reason, for the field permissions matrix.
      def permissions
        return if invalid_project_selection?
        return unless @roles.present? && @trackers.present?

        @project_workflow_scope_state = scope_state_for(ProjectWorkflowScope::PERMISSIONS)
        @fields = (Tracker::CORE_FIELDS_ALL - @trackers.map(&:disabled_core_fields).reduce(:&)).map do |field|
          [field, l("field_#{field.delete_suffix('_id')}")]
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
        return if invalid_project_selection?

        if project_context?
          if @roles.present? && @trackers.present? && params[:permissions]
            permissions = strip_no_change(normalize_permissions_params(params[:permissions]))
            result = RedmineProjectWorkflows::Services::MatrixSaveResult.none
            ActiveRecord::Base.transaction do
              result = selected_project_ids.sum(result) do |project_id|
                RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
                  project_id,
                  @trackers,
                  @roles,
                  permissions
                )
              end
            end
            report_matrix_save(result)
          end
          redirect_to permissions_workflows_path(project_id: selected_project_param_values, tracker_id: @trackers,
                                                 role_id: @roles, used_statuses_only: params[:used_statuses_only])
        else
          super
        end
      end

      def copy
        load_project_options
        return if invalid_project_selection?

        @source_project_id = params[:source_project_id].presence
        super
      end

      # load_project_options is here for its @projects side effect alone -- the
      # copy form's two project selectors are `source_project_id` and
      # `target_project_ids[]`, and it builds the list both are rendered from.
      #
      # Deliberately no `invalid_project_selection?` after it, unlike #copy: this
      # action never reads params[:project_id], so an id in it names nothing and
      # can widen nothing, and answering 404 for a parameter the action ignores
      # would be reporting a fault that does not exist. The two selectors it does
      # read are validated in full below and in validated_target_project_ids,
      # shape as well as record (finding F07).
      def duplicate
        load_project_options
        find_sources_and_targets
        return if invalid_copy_selection?
        return super unless project_context?

        source_project_id = params[:source_project_id].presence
        resolved_target_project_ids, invalid_target_project_ids = validated_target_project_ids
        if params[:source_tracker_id].blank? || params[:source_role_id].blank? ||
           (@source_tracker.nil? && @source_role.nil?) ||
           (source_project_id.present? && %w[any global].exclude?(source_project_id) &&
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
          copied = []
          ActiveRecord::Base.transaction do
            resolved_target_project_ids.each do |target_project_id|
              pairs = WorkflowRule.copy_for_project(
                resolved_copy_source(source_project_id, target_project_id),
                target_project_id,
                @source_tracker,
                @source_role,
                @target_trackers,
                @target_roles
              )
              copied.concat(
                RedmineProjectWorkflows::Services::ScopeCombinations.for_project(target_project_id, pairs)
              )
            end
            record_scopes_for_copy(copied)
          end
          report_copy(copied)
          redirect_to copy_workflows_path(
            source_tracker_id: @source_tracker,
            source_role_id: @source_role,
            source_project_id: source_project_id
          )
        end
      end

      private

      # What a matrix save did, and what it deliberately did not do.
      #
      # A combination that still inherits the generic workflow is left alone
      # (INV-3: taking a workflow over is one of the three scope actions, not a
      # side effect of pressing Save), and saying so is not optional -- the grid
      # shows what the selection *stores*, so an inheriting combination renders
      # empty, and a silent no-op there is indistinguishable from a save that
      # cleared it.
      #
      # The counts come from the writers rather than being inferred here. This
      # method used to compute what had been written as (projects x trackers x
      # roles) - skipped, which is right only while "not refused" means
      # "written": a payload the writer's whitelist had emptied refuses nothing,
      # so the whole selection was reported saved over a table nothing had
      # touched (finding F06). MatrixSaveResult carries both counts, and the
      # third case -- nothing written, nothing refused -- now gets a message of
      # its own instead of the success notice.
      def report_matrix_save(result)
        flash[:notice] = l(:notice_successful_update) if result.written?
        if result.skipped?
          flash[:warning] = l(:notice_project_workflow_save_skipped_inheriting, count: result.skipped)
        elsif result.nothing_applied?
          flash[:warning] = l(:notice_project_workflow_save_nothing_applied)
        end
      end

      # Strips core's "no change" option out of a submitted matrix, at whatever
      # depth the leaves are: transitions nest status/status/rule and
      # permissions status/field.
      #
      # Guarded, unlike core's own two loops: `transitions[1]=x` reaches those
      # as a String and raises NoMethodError on `each_value`, which is a 500
      # rather than a rejection. ProjectWorkflowsController has guarded its own
      # copy since WP4; these are the same parameters through a different door.
      def strip_no_change(params)
        hash = to_plain_hash(params)
        hash.each_value { |value| strip_no_change_in(value) }
        hash
      end

      def strip_no_change_in(value)
        return unless value.is_a?(Hash)

        value.reject! { |_key, inner| inner == 'no_change' }
        value.each_value { |inner| strip_no_change_in(inner) }
      end

      def to_plain_hash(value)
        return {} if value.nil?
        return value.deep_dup.to_unsafe_h if value.respond_to?(:to_unsafe_h)

        value.respond_to?(:to_h) ? value.to_h.deep_dup : {}
      end

      # The copy form's "which workflow" selectors, checked before anything is
      # written, because every write on this screen first deletes what the
      # target pair already had.
      #
      # Core cannot tell a selection from a mistake here. A source tracker or
      # role that names nothing resolves to nil -- which is also how "same as
      # the target" is spelled -- so a stale form naming a deleted tracker
      # copies from every tracker instead of being reported (codex F01). A
      # target tracker or role that names nothing is dropped from core's
      # `where(id: ...)`, so a selection of one live tracker and one deleted
      # one is applied to the live one and reported as a success (codex F02).
      # Both are the rule the target *projects* have been held to since WP0,
      # applied to the four selectors that had never been held to it: source
      # tracker, source role, target trackers, target roles.
      #
      # Checked for every request, not only for one that names a project: the
      # copy form always renders both project selectors, but a multiple select
      # with nothing selected submits nothing at all, and such a request is
      # handed to core.
      def invalid_copy_selection?
        if unresolved_source_selection?
          @source_project_id = nil
          flash.now[:error] = l(:error_workflow_copy_source)
        elsif unresolved_target_selection?
          @source_project_id = params[:source_project_id].presence
          flash.now[:error] = l(:error_workflow_copy_target_tracker_or_role)
        else
          return false
        end
        render :copy
        true
      end

      def unresolved_source_selection?
        unresolved_source?(params[:source_tracker_id], @source_tracker) ||
          unresolved_source?(params[:source_role_id], @source_role)
      end

      # 'any' is a selection, and a selector left blank is already reported by
      # the branch that owns it -- the project branch below, or core's own on a
      # request that named no project. An id of any other shape has to resolve
      # to the record it names, and the shape is checked as well as the record,
      # because core resolves the id with `to_i`, so '12abc' silently means
      # tracker 12.
      def unresolved_source?(value, record)
        value = value.to_s
        return false if value.blank? || value == 'any'

        !value.match?(/\A\d+\z/) || record.nil?
      end

      def unresolved_target_selection?
        unresolved_target_ids(params[:target_tracker_ids], @target_trackers).present? ||
          unresolved_target_ids(params[:target_role_ids], @target_roles).present?
      end

      # The submitted ids that no record answered, de-duplicated the same way
      # validated_target_project_ids de-duplicates: an id repeated in the
      # selection is one selection, not a missing record.
      def unresolved_target_ids(values, records)
        submitted = Array.wrap(values).reject(&:blank?).map(&:to_s).uniq
        submitted - Array.wrap(records).map { |record| record.id.to_s }
      end

      # A copy that lands in a project has to record the decision as well, or the
      # resolver ignores every row it just wrote (INV-3). copy_for_project moves
      # both kinds of rule, so both rule types are considered -- but a scope is
      # created only where the target now *has* rules, because an empty
      # transitions scope would stop every issue in the project from changing
      # status. A targeted pair that already carried rules without a scope gets
      # one too; that is a repair, not an over-reach, and it can only happen to
      # a pair the operator named.
      #
      # The combinations are the ones the copy actually copied, not the ones it
      # was aimed at: a pair whose source resolves to the target itself is
      # skipped, and stamping its audit columns said somebody had changed a
      # workflow nothing had changed (finding F04).
      def record_scopes_for_copy(combinations)
        RedmineProjectWorkflows::Services::ScopeWriter.ensure_scopes_for_copy(
          combinations: combinations,
          user: User.current
        )
      end

      # Which workflow a copy reads from, per target project. 'any' means each
      # target project's own; blank or 'global' mean the generic one; anything
      # else is the project the form named.
      def resolved_copy_source(source_project_id, target_project_id)
        return target_project_id if source_project_id == 'any'
        return nil if source_project_id.blank? || source_project_id == 'global'

        source_project_id
      end

      # What the copy did, including the part nobody asked for: a combination it
      # left with an own *empty* workflow. See ScopeCombinations.own_empty_count --
      # reported rather than refused, because the copy is also how somebody
      # deliberately empties a project (finding F03).
      def report_copy(combinations)
        flash[:notice] = l(:notice_successful_update)
        emptied = RedmineProjectWorkflows::Services::ScopeCombinations.own_empty_count(combinations)
        flash[:warning] = l(:notice_project_workflow_copy_left_empty, count: emptied) if emptied.positive?
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

      def normalize_permissions_params(permissions)
        permissions = to_plain_hash(permissions)
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

      # Core declares this callback *before* `require_admin`, so nothing in it may
      # render. Rendering from a before_action halts the chain, and the 404 for
      # an unresolvable project id was therefore answered before anyone had
      # checked who was asking: /workflows/edit told an anonymous visitor which
      # project ids exist, answering 404 for one that does not and a redirect to
      # the login page for one that does (finding G01). The invalid ids are
      # collected here and every action decides, after authorization.
      def find_trackers_roles_and_statuses_for_edit
        find_roles
        find_trackers
        load_project_options
        find_statuses
      end

      # "Only display statuses that are used by this tracker" -- the checkbox
      # above both matrices.
      #
      # It used to filter on the physically selected project ids, so for a
      # project that inherits it found no rows at all, .presence then fell back
      # to *every* status, and the filter silently switched itself off in exactly
      # the case where it was wanted (external F04). It now asks for the
      # effective workflow of the selection: a project that inherits answers with
      # the generic statuses, one with its own workflow answers with its own, and
      # a project whose workflow is deliberately empty answers with nothing --
      # which still falls back to every status, because that is the only way an
      # administrator can fill an empty matrix in.
      #
      # The role filter is core's own, kept as it is: the question is which
      # statuses the workflow uses, not which the selected roles use.
      def find_statuses
        @used_statuses_only = params[:used_statuses_only] != '0'
        if @trackers && @used_statuses_only
          status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_pairs(
            pairs: workflow_project_ids.product(@trackers.map(&:id)),
            role_ids: Role.all.select(&:consider_workflow?).map(&:id)
          )
          @statuses = IssueStatus.where(id: status_ids).sorted.to_a.presence
        end
        @statuses ||= IssueStatus.sorted.to_a
      end
    end
  end
end
