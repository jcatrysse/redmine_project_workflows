# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Decides, per role, whether a project runs its own workflow or inherits the
    # generic one.
    #
    # The answer comes from ProjectWorkflowScope and from nothing else. Asking
    # whether rule rows exist -- what the plugin did before ADR-001 -- cannot
    # express a deliberately empty workflow and silently returned a project to
    # inheritance when its last rule was removed (INV-3).
    class Resolver
      # Role ids that have a scope for this project, tracker and rule type.
      #
      # Cached for the length of the request: an issue list renders many issues
      # of the same tracker in the same project, and this sits on the path of
      # every one of them. The lookup is deliberately not narrowed by role, so
      # that one cached entry answers for every set of roles a request meets.
      # It reads the leading columns of the unique index, so it stays a point
      # lookup (INV-6).
      def self.scoped_role_ids(project_id:, tracker_id:, rule_type:)
        return [] if project_id.blank? || tracker_id.blank?

        key = [project_id.to_i, tracker_id.to_i, rule_type.to_s]
        cache = (RedmineProjectWorkflows::Current.scoped_role_ids ||= {})
        cache[key] ||= ProjectWorkflowScope.where(
          project_id: key[0],
          tracker_id: key[1],
          rule_type: key[2]
        ).distinct.pluck(:role_id)
      end

      # Called after any write that creates or removes a scope, so that a
      # request which changes the configuration and then reads it back does not
      # answer from the cache it has just invalidated.
      def self.reset_cache!
        RedmineProjectWorkflows::Current.scoped_role_ids = nil
      end

      def initialize(project_id:, tracker_id:, role_ids:)
        @project_id = project_id
        @tracker_id = tracker_id
        @role_ids = Array(role_ids).compact.map(&:to_i)
      end

      # The roles this project answers for itself. Accepts WorkflowTransition,
      # WorkflowPermission or a rule type string.
      def overridden_role_ids_for(model)
        return [] if @role_ids.empty? || @project_id.blank? || @tracker_id.blank?

        rule_type = ProjectWorkflowScope.rule_type_for(model)
        @role_ids & self.class.scoped_role_ids(
          project_id: @project_id,
          tracker_id: @tracker_id,
          rule_type: rule_type
        )
      end

      # The roles that fall back to the generic workflow.
      def global_role_ids_for(model)
        @role_ids - overridden_role_ids_for(model)
      end
    end
  end
end
