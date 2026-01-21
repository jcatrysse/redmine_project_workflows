# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class StatusListQuery
      def self.status_ids_for_project(project:, trackers:, role_ids: nil)
        new(project: project, trackers: trackers, role_ids: role_ids).status_ids
      end

      def initialize(project:, trackers:, role_ids: nil)
        @project = project
        @trackers = Array(trackers).compact
        @role_ids = role_ids
      end

      def status_ids
        return [] if @trackers.empty?

        role_ids = resolved_role_ids
        return [] if role_ids.empty?

        scopes = build_scopes(role_ids)
        return [] if scopes.empty?

        combined_scope = scopes.shift
        scopes.each { |scope| combined_scope = combined_scope.or(scope) }

        combined_scope.pluck(:old_status_id, :new_status_id).flatten.uniq
      end

      private

      def resolved_role_ids
        return Role.all.select(&:consider_workflow?).map(&:id) if @role_ids.nil?

        Array(@role_ids).compact
      end

      def build_scopes(role_ids)
        base_scope = WorkflowTransition.where('old_status_id <> new_status_id')
        tracker_ids = @trackers.map(&:id)
        overrides = WorkflowTransition.where(
          project_id: @project&.id,
          tracker_id: tracker_ids,
          role_id: role_ids
        ).distinct.pluck(:tracker_id, :role_id)

        overridden_role_ids_by_tracker = Hash.new { |hash, key| hash[key] = [] }
        overrides.each do |tracker_id, role_id|
          overridden_role_ids_by_tracker[tracker_id] << role_id
        end

        scopes = []
        @trackers.each do |tracker|
          overridden_role_ids = overridden_role_ids_by_tracker[tracker.id]
          global_role_ids = role_ids - overridden_role_ids
          tracker_scopes = []

          if overridden_role_ids.any?
            tracker_scopes << base_scope.where(
              tracker_id: tracker.id,
              role_id: overridden_role_ids,
              project_id: @project&.id
            )
          end
          if global_role_ids.any?
            tracker_scopes << base_scope.where(
              tracker_id: tracker.id,
              role_id: global_role_ids,
              project_id: nil
            )
          end

          next if tracker_scopes.empty?

          tracker_scope = tracker_scopes.shift
          tracker_scopes.each { |scope| tracker_scope = tracker_scope.or(scope) }
          scopes << tracker_scope
        end

        scopes
      end
    end
  end
end
