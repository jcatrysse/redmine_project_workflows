# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The two populations one project's roles resolve to, as finished relations.
    #
    # A set of roles read for one (project, tracker) never comes from one place:
    # the roles the project answers for itself read the project's own rows, and
    # the rest read the generic ones (INV-5 -- a scope replaces, so a role is in
    # exactly one of the two). Which roles are in which comes from the scope
    # table through the Resolver's cached point lookup, never from whether rule
    # rows exist (INV-3) and never by walking the project tree (INV-6).
    #
    # **Finished relations, never a base relation carrying only the tracker.**
    # That is the whole reason this is extracted rather than written twice.
    # INV-4 says every query against +workflows+ carries an explicit project_id;
    # a helper that handed back a relation narrowed by tracker alone, for the
    # caller to add a project_id to, would be INV-4's discipline with one more
    # place to get it wrong -- and a relation that mixes both populations if
    # anything ever executed it. Here a relation cannot be built without a
    # project_id: nil for the generic rows, an id for a project's own.
    #
    # Four callers: TransitionQuery and PermissionQuery -- the resolver itself,
    # and the two hottest paths the plugin owns -- plus TransitionMapQuery (WP8)
    # and WorkflowGraphQuery (WP9). What they share is exactly this split and
    # nothing else -- one asks which statuses an issue may move to, the next
    # which fields it may change, the third the edges around one status, the
    # last the whole graph -- which is why the split is what was extracted and
    # not a base class.
    class WorkflowPopulations
      # One relation per population that has any role in it, in a fixed order:
      # the project's own rows first, the generic rows second. Empty when there
      # is nothing to ask about, so a caller can test it rather than guess.
      #
      # +model+ is WorkflowTransition or WorkflowPermission -- the Resolver reads
      # the rule type off it, so the scope lookup and the rows can never describe
      # different kinds of rule.
      #
      # A blank +project_id+ is not an error and does not answer nothing: an
      # issue that has no project yet reads the generic workflow, which is the
      # choice Issue#new_statuses_allowed_to and Issue#tracker= already make and
      # which this is now the only implementation of. No project means no scope
      # can exist, so the Resolver answers "nothing overridden" and every role
      # falls into the generic half -- one relation, still carrying an explicit
      # +project_id: nil+ (INV-4).
      def self.scopes(model:, project_id:, tracker_id:, role_ids:)
        ids = Array(role_ids).compact.map(&:to_i).uniq
        return [] if ids.empty? || tracker_id.blank?

        own = Resolver.new(project_id: project_id, tracker_id: tracker_id, role_ids: ids)
                      .overridden_role_ids_for(model)
        generic = ids - own

        scopes = []
        scopes << relation(model, project_id, tracker_id, own) if own.any?
        scopes << relation(model, nil, tracker_id, generic) if generic.any?
        scopes
      end

      # The same two relations OR'd into one, or nil when there is nothing to
      # ask. Built before anything narrows it, because .or refuses a relation
      # that has already been distinct'ed or ordered -- so a caller adds its own
      # conditions to what comes back, never to the halves.
      def self.combined(model:, project_id:, tracker_id:, role_ids:)
        scopes = scopes(model: model, project_id: project_id, tracker_id: tracker_id, role_ids: role_ids)
        return nil if scopes.empty?

        scopes.reduce { |combined, scope| combined.or(scope) }
      end

      # INV-4 made structural: this is the only place either caller builds a
      # relation on +workflows+, and the project_id is a positional argument
      # rather than an option, so it cannot be forgotten.
      def self.relation(model, project_id, tracker_id, role_ids)
        model.where(project_id: project_id, tracker_id: tracker_id, role_id: role_ids)
      end
      private_class_method :relation
    end
  end
end
