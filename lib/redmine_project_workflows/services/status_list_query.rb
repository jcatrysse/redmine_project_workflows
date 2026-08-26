# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Which statuses appear anywhere in the workflow of a project, per tracker.
    #
    # Which of the two populations a (tracker, role) reads comes from the scope
    # table, never from whether rule rows exist. A project with a scope and no
    # rules contributes nothing, which is what an empty workflow means.
    #
    # The unit of work is a (project, tracker) pair, because two projects can
    # answer for the same tracker differently and nothing is inherited between
    # them (INV-6). A whole project tree is therefore one call with many pairs,
    # not one call per project: the number of queries does not grow with the
    # size of the tree.
    class StatusListQuery
      # Many (project_id, tracker_id) pairs at once. A nil project id in a pair
      # is the generic workflow.
      #
      # +role_ids+ nil means "no role filter", which is what core does
      # everywhere it reads this table. Passing a list narrows the answer to
      # those roles; passing an empty list answers nothing.
      def self.status_ids_for_pairs(pairs:, role_ids: nil)
        new(pairs: pairs, role_ids: role_ids).status_ids
      end

      # The project-aware answer to core's Tracker#issue_status_ids: which
      # statuses this project's effective workflow for this tracker uses, with
      # no role filter, exactly as core asks it of the tracker alone.
      #
      # Cached for the length of the request. See Current#effective_status_ids
      # for why, and Resolver.reset_cache! for what invalidates it.
      def self.effective_status_ids(project:, tracker:)
        return [] if tracker.nil? || (tracker.is_a?(Tracker) && tracker.new_record?)

        key = [
          project.is_a?(Project) ? project.id : project&.to_i,
          tracker.is_a?(Tracker) ? tracker.id : tracker.to_i
        ]
        cache = (RedmineProjectWorkflows::Current.effective_status_ids ||= {})
        cache[key] ||= status_ids_for_pairs(pairs: [key])
      end

      # Integer() rather than to_i on purpose: to_i turns a missing tracker id
      # into 0 and a *flat* pair list into one pair per element with tracker 0,
      # both of which answer [] instead of saying the caller is wrong.
      def initialize(pairs:, role_ids: nil)
        @pairs = Array(pairs).map do |pair|
          project_id, tracker_id = pair
          [project_id && Integer(project_id), Integer(tracker_id)]
        end.uniq
        @role_ids = role_ids.nil? ? nil : Array(role_ids).compact.map { |id| Integer(id) }.uniq
      end

      def status_ids
        return [] if @pairs.empty? || @role_ids&.empty?

        conditions = build_conditions
        return [] if conditions.empty?

        combined = conditions.shift
        conditions.each { |condition| combined = combined.or(condition) }

        combined.distinct.pluck(:old_status_id, :new_status_id).flatten.uniq
      end

      private

      def base_scope
        WorkflowTransition.where('old_status_id <> new_status_id')
      end

      # One condition per pair that overrides something, plus one per tracker
      # for the generic rows that are still reachable. In the common case --
      # nothing overridden anywhere -- that is one condition per tracker,
      # whatever the size of the project tree.
      def build_conditions
        scoped = scoped_role_ids_by_pair
        conditions = []

        @pairs.each do |project_id, tracker_id|
          own_role_ids = scoped[[project_id, tracker_id]]
          next if own_role_ids.blank?

          conditions << base_scope.where(project_id: project_id, tracker_id: tracker_id, role_id: own_role_ids)
        end

        generic_conditions(scoped) + conditions
      end

      # A generic row for (tracker, role) is still reachable unless *every* pair
      # for that tracker answers for that role itself. One project overriding a
      # role says nothing about the next project in the tree (INV-6).
      def generic_conditions(scoped)
        @pairs.group_by { |_project_id, tracker_id| tracker_id }.filter_map do |tracker_id, pairs|
          excluded = pairs.map { |pair| scoped[pair] || [] }.reduce(&:&) || []
          generic_condition(tracker_id, excluded)
        end
      end

      # nil when this tracker has nothing generic left to read: every role the
      # caller asked about is answered by the projects themselves.
      def generic_condition(tracker_id, excluded_role_ids)
        scope = base_scope.where(project_id: nil, tracker_id: tracker_id)
        return excluded_role_ids.any? ? scope.where.not(role_id: excluded_role_ids) : scope if @role_ids.nil?

        role_ids = @role_ids - excluded_role_ids
        return nil if role_ids.empty?

        scope.where(role_id: role_ids)
      end

      # {[project_id, tracker_id] => [role_id, ...]} for the pairs that have a
      # transitions scope. One query for every pair (INV-4: the predicate is
      # explicit, and a pair whose project id is nil cannot have a scope).
      def scoped_role_ids_by_pair
        project_ids = @pairs.filter_map(&:first).uniq
        return {} if project_ids.empty?

        scope = ProjectWorkflowScope.where(
          project_id: project_ids,
          tracker_id: @pairs.map(&:last).uniq,
          rule_type: ProjectWorkflowScope::TRANSITIONS
        )
        scope = scope.where(role_id: @role_ids) if @role_ids

        wanted = @pairs.to_set
        rows = scope.distinct.pluck(:project_id, :tracker_id, :role_id)
        rows.each_with_object({}) do |(project_id, tracker_id, role_id), map|
          key = [project_id, tracker_id]
          next unless wanted.include?(key)

          (map[key] ||= []) << role_id
        end
      end
    end
  end
end
