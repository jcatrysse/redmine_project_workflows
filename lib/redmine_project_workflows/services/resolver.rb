# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class Resolver
      def initialize(project_id:, tracker_id:, role_ids:)
        @project_id = project_id
        @tracker_id = tracker_id
        @role_ids = Array(role_ids)
      end

      def overridden_role_ids_for(model)
        return [] if @role_ids.empty? || @project_id.blank? || @tracker_id.blank?

        model.where(
          project_id: @project_id,
          tracker_id: @tracker_id,
          role_id: @role_ids
        ).distinct.pluck(:role_id)
      end

      def global_role_ids_for(model)
        @role_ids - overridden_role_ids_for(model)
      end
    end
  end
end
