# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowsControllerPatch
      # How a request names projects, and what it resolves to. See that module:
      # every method it adds is private, because this one is prepended to a
      # controller.
      include RedmineProjectWorkflows::WorkflowSelection
      # The copy screen's own vocabulary -- #duplicate's four private helpers.
      # Both modules live outside Patches since ADR-003: they are the plugin's
      # own controller code, shared with the plugin's own administration
      # controller, and only ever sat under Patches because these actions did.
      # Every method in them is private, because a public instance method of a
      # controller is an action.
      include RedmineProjectWorkflows::CopyScopes

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
          @rule_type_for_log = ProjectWorkflowScope::TRANSITIONS
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
          @rule_type_for_log = ProjectWorkflowScope::PERMISSIONS
          if @roles.present? && @trackers.present? && params[:permissions]
            # strip_no_change already does the to_plain_hash conversion, and
            # PermissionWriter's whitelist rejects any key that is not a
            # real status id, so the whitelist is unchanged by dropping the
            # transposition that used to sit here.
            #
            # What went (finding F14): fifteen lines that turned
            # permissions[field][status] into permissions[status][field] for a
            # payload shape nothing produces. WorkflowsHelper#field_permission_tag
            # emits `permissions[<status>][<field>]` on 5.1, 6.1 and 7.0 alike --
            # checked in all three checkouts -- and so does the plugin's own
            # project-level grid, which calls the same helper. Core's own
            # update_permissions names its block variables `field` and
            # `rule_by_status_id`, as though the payload were field-first, which
            # is stale naming rather than a second shape; reading the controller
            # instead of the view is the easy way to conclude otherwise.
            #
            # It also had a live edge: a *mixed* payload whose first key was not
            # numeric took the transposed branch and silently discarded the real
            # matrix.
            permissions = strip_no_change(params[:permissions])
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
            lock_scopes_for_copy(source_project_id, resolved_target_project_ids)
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
        warnings = []
        if result.skipped?
          warnings << l(:notice_project_workflow_save_skipped_inheriting, count: result.skipped)
        elsif result.nothing_applied?
          warnings << l(:notice_project_workflow_save_nothing_applied)
        end
        # The mixed case: some entries written, some dropped by the whitelist. It
        # had no message at all -- `written` was positive, so the screen reported
        # a plain success and said nothing about the refused part (finding F06 of
        # the 2026-08-27-bundled run). Appended, because which part was refused is
        # additional information about the save rather than an alternative to
        # reporting it.
        rejected = result.rejected
        warnings << l(:notice_project_workflow_save_rejected_values, count: rejected) if rejected.positive?
        flash[:warning] = warnings.join(' ') if warnings.any?
        log_matrix_save(result)
      end

      # Ids and counts, never the matrix (finding F19). This is the write that
      # can touch every project on the installation in one transaction, so it is
      # the one whose absence from the log cost the most.
      def log_matrix_save(result)
        RedmineProjectWorkflows::Services::WriteLog.record(
          'admin_matrix_save',
          rule_type: @rule_type_for_log,
          actor: User.current.id,
          projects: selected_project_ids,
          trackers: @trackers&.map(&:id),
          roles: @roles&.map(&:id),
          written: result.written, skipped: result.skipped, rejected: result.rejected
        )
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

      # See MatrixParams#to_plain_hash for the reasoning; this is the
      # administration screens' own copy, deliberately not shared (finding F14),
      # and it had the same gap. `respond_to?(:to_h)` is true of an Array, whose
      # `to_h` raises TypeError -- so `?transitions[]=x` was a 500 from inside
      # the guard that exists to prevent one (finding F02 of the
      # 2026-08-27-bundled-followup run). What it is, not what it answers to.
      #
      # The deep_dup stays: strip_no_change mutates what it is given with
      # reject!, and these parameters belong to the request.
      def to_plain_hash(value)
        return value.deep_dup.to_unsafe_h if value.respond_to?(:to_unsafe_h)

        value.is_a?(Hash) ? value.deep_dup : {}
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

      # Core declares this callback *before* `require_admin`, so nothing in it may
      # render. Rendering from a before_action halts the chain, and the 404 for
      # an unresolvable project id was therefore answered before anyone had
      # checked who was asking: /workflows/edit told an anonymous visitor which
      # project ids exist, answering 404 for one that does not and a redirect to
      # the login page for one that does (finding G01). The invalid ids are
      # collected here and every action decides, after authorization.
      # The guard prepares data and does not authorize: `require_admin`, declared
      # after this callback, still decides, and every consumer of @trackers,
      # @statuses and @projects runs after it. Returning early only means a
      # request that is going to be refused does not pay for the preparation
      # first (finding F05). `user_setup` is registered in ApplicationController
      # before WorkflowsController's own callbacks on all three supported
      # versions, so User.current is already correct here.
      #
      # What it stops: with ?project_id[]=all&tracker_id[]=all an anonymous GET
      # ran Project.sorted.map(&:id) over every project row, one scope query
      # with an IN list of every project id, and one OR query with a branch per
      # (project, tracker) that overrides something. Core runs one bounded
      # WorkflowTransition query here, so this is an amplification of core's own
      # ordering rather than a new exposure -- but core's scales with the number
      # of trackers and the plugin's with the number of projects.
      #
      # Deliberately NOT a second `require_admin`, scoped with `only:`.
      # docs/DECISIONS.md:93 rejected that once; the sharper reason is that
      # ActiveSupport's callback dedupe compares only kind and filter, and
      # `only:` is stored as a separate `:if` condition -- so prepending one
      # would *remove* core's unconditional registration and leave `index`,
      # `copy` and `duplicate` ungated. See docs/STATE.md's traps list.
      def find_trackers_roles_and_statuses_for_edit
        return unless User.current.admin?

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
