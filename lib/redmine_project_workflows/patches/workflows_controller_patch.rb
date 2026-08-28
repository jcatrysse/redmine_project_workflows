# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # What Redmine's own workflow administration screens get wrong once the
    # `workflows` table has a `project_id` column, and nothing else (ADR-003).
    #
    # Every query core runs here is written for a table in which every row is
    # generic. Add a project dimension and those queries read a project's rules
    # as the installation's: the summary page counted a project's transitions
    # into the generic totals, so a project that had taken one tracker over made
    # the generic workflow look like it had rules it does not have (claude F01).
    # That is INV-4 -- a workflow query with no `project_id` predicate silently
    # mixes two populations -- and it is the whole of what remains here.
    #
    # **Everything about projects is gone from this file**, and gone from core's
    # screens with it: the selector, the scope panel, the summary counts, the
    # copy form's project selectors, the bulk reporting and the copy validation
    # are all on `ProjectWorkflowRulesController` and the plugin's own views
    # (WP12). This patch was 468 lines replacing six core actions; the project
    # dimension living inside a core controller was the cost ADR-003 removed.
    #
    # **Why these three actions and one finder, when ADR-003's own list names
    # five.** The list in the ADR is the actions whose *screens* show or store
    # the generic workflow, and it was written without checking where the write
    # is isolated. `update` and `update_permissions` need nothing here:
    # `WorkflowTransition.replace_transitions` and
    # `WorkflowPermission.replace_permissions` are routed through the plugin's
    # writers by their own patches, with `project_id` fixed at `nil`, so core's
    # own bodies already write generic rows and only generic rows (INV-1). What
    # the ADR's list missed is `find_statuses`, whose "only display statuses that
    # are used by this tracker" query is a `workflows` query like any other and
    # would otherwise offer the generic matrix a status only some project's own
    # workflow uses.
    #
    # A parameter cannot widen any of this: none of these bodies reads
    # `params[:project_id]`, so an id in the query string of a core workflow URL
    # names nothing and reaches nothing (INV-7).
    module WorkflowsControllerPatch
      # The generic workflow's own totals. Core's two `@roles` / `@trackers`
      # lines are byte-identical in Redmine 5.1, 6.1 and 7.0; only the count
      # gains its predicate.
      #
      # Rewritten rather than called through `super` and corrected afterwards,
      # because super's query *is* the defect: running it and discarding the
      # answer would still be a workflow query with no `project_id` predicate.
      def index
        @roles = Role.sorted.select(&:consider_workflow?)
        @trackers = Tracker.sorted
        @workflow_counts = WorkflowTransition.where(project_id: nil)
                                             .group(:tracker_id, :role_id).count
      end

      # The status transitions matrix, for the generic workflow.
      def edit
        return unless @trackers.present? && @roles.present? && @statuses.any?

        workflows = WorkflowTransition
                    .where(role_id: @roles.map(&:id), tracker_id: @trackers.map(&:id), project_id: nil)
                    .preload(:old_status, :new_status)
        @workflows = {
          'always' => workflows.reject { |workflow| workflow.author || workflow.assignee },
          'author' => workflows.select(&:author),
          'assignee' => workflows.select(&:assignee)
        }
      end

      # See #edit: the same reason, for the field permissions matrix. Core reads
      # it with `WorkflowPermission.rules_by_status_id`, which has no predicate
      # either; the plugin's query service takes the population as an argument.
      def permissions
        return unless @roles.present? && @trackers.present?

        @fields = (Tracker::CORE_FIELDS_ALL - @trackers.map(&:disabled_core_fields).reduce(:&)).map do |field|
          [field, l("field_#{field.delete_suffix('_id')}")]
        end
        @custom_fields = @trackers.map(&:custom_fields).flatten.uniq.sort
        @permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(
          @trackers, @roles, [nil]
        )
        @statuses.each { |status| @permissions[status.id] ||= {} }
      end

      private

      # "Only display statuses that are used by this tracker" -- the checkbox
      # above both matrices, answered for the generic workflow alone.
      #
      # Core's own body pays no attention to `project_id`, so on an installation
      # where one project has taken a tracker over the generic matrix grew rows
      # for statuses no generic rule mentions. The role filter is core's own,
      # kept as it is: the question is which statuses the workflow uses, not
      # which the selected roles use.
      def find_statuses
        @used_statuses_only = params[:used_statuses_only] != '0'
        if @trackers && @used_statuses_only
          status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_pairs(
            pairs: @trackers.map { |tracker| [nil, tracker.id] },
            role_ids: Role.all.select(&:consider_workflow?).map(&:id)
          )
          @statuses = IssueStatus.where(id: status_ids).sorted.to_a.presence
        end
        @statuses ||= IssueStatus.sorted.to_a
      end
    end
  end
end
