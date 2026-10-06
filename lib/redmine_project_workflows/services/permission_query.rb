# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The field-permissions half of the resolver. Like TransitionQuery, it
    # replaces core's lookup instead of falling back to it: core queries
    # workflows without a project_id predicate (INV-4).
    class PermissionQuery
      # The two populations come from WorkflowPopulations rather than from a
      # base relation narrowed here and given a project_id on each branch
      # (finding F02 of 2026-08-28, second run). The old shape answered
      # correctly -- every branch did add one -- but it held a relation on
      # +workflows+ with no project_id in it, which is the very thing INV-4's
      # own grep looks for, and a fourth branch or a +to_a+ moved one line up
      # would have turned a safe pattern into a silent population mix with no
      # test that would notice. Here there is no half to execute.
      def self.rules_for(issue:, user:, old_status_id:)
        roles = issue.send(:roles_for_workflow, user)
        return [] if roles.empty?

        combined = WorkflowPopulations.combined(
          model: WorkflowPermission, project_id: issue.project_id,
          tracker_id: issue.tracker_id, role_ids: roles.map(&:id)
        )
        return [] if combined.nil?

        # Added to what comes back, never to the halves: .or refuses a relation
        # that has already been narrowed differently on the two sides.
        combined.where(old_status_id: old_status_id).to_a
      end

      def self.rules_by_status_id_for_project(trackers, roles, project_ids)
        WorkflowPermission.where(
          tracker_id: trackers.map(&:id),
          role_id: roles.map(&:id),
          project_id: project_ids
        ).each_with_object({}) do |rule, hash|
          hash[rule.old_status_id] ||= {}
          hash[rule.old_status_id][rule.field_name] ||= []
          hash[rule.old_status_id][rule.field_name] << rule.rule
        end
      end
    end
  end
end
