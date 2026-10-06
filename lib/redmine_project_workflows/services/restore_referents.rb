# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The referents a restore resolves against: what a rule is made of *now*.
    #
    # Out of WorkflowRestore and into a file of its own for the ordinary reason
    # -- the class had grown past the length the linter allows -- but it earns
    # the move: this is the whole of what a backup is checked against, and it is
    # the answer to "what did this installation outlive". Nothing here writes.
    #
    # The three things a rule is made of, plus the users its audit columns name
    # and the combinations that already have a decision. Loaded once: asking per
    # combination would be six queries per row of a file that can hold one per
    # project, tracker and role on the installation.
    RestoreReferents = Struct.new(:projects, :trackers, :roles, :users, :scoped) do
      def missing(key)
        project_id, tracker_id, role_id, rule_type = key
        gone = []
        gone << "project #{project_id}" unless projects.include?(project_id)
        gone << "tracker #{tracker_id}" unless trackers.key?(tracker_id)
        gone << "role #{role_id}" unless roles.key?(role_id)
        gone << "rule type #{rule_type.inspect}" unless ProjectWorkflowScope::RULE_TYPES.include?(rule_type)
        return nil if gone.empty?

        "skipped #{rule_type} for project #{project_id}, tracker #{tracker_id}, " \
          "role #{role_id}: #{gone.join(', ')} not found"
      end

      def scoped?(key) = scoped.include?(key)

      # Nil for a user deleted since the export, which is what the column
      # already means. An endless method would swallow the guard.
      def user_id(id)
        id if id && users.include?(id)
      end
    end
  end
end
