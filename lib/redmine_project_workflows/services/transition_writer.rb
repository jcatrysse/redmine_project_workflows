# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class TransitionWriter
      extend MatrixScope

      # The workflow class this writer owns; MatrixScope builds its predicates
      # from it.
      def self.rule_model
        WorkflowTransition
      end

      # The three columns of the transitions matrix, which are three *controls*
      # over one (old status, new status) cell -- and, in the table, two rows:
      # the unconditional one (author and assignee both false) and the one
      # carrying whichever of the two flags apply. Core keeps them apart per
      # rule, and so must this.
      RULES = %w[always author assignee].freeze
      ALWAYS = 'always'
      AUTHOR = 'author'
      ASSIGNEE = 'assignee'
      # What the matrix can submit for one cell: the checkbox and its paired
      # hidden field. 'no_change' is stripped by the controller; anything else
      # is not something the form can produce.
      VALUES = ['0', '1', true, false].freeze
      # Core stores transitions out of the "new issue" pseudo status as
      # old_status_id 0, which is not an IssueStatus.
      NEW_ISSUE_STATUS_ID = '0'

      def self.replace_transitions(project, trackers, roles, transitions)
        replace_transitions_for_project_id(project.id, trackers, roles, transitions)
      end

      # Returns the number of (tracker, role) combinations this call refused to
      # write because the project still inherits the generic workflow. Zero for
      # a generic write, which has no scope to check.
      def self.replace_transitions_for_project_id(project_id, trackers, roles, transitions)
        trackers = Array.wrap(trackers)
        roles = Array.wrap(roles)
        return 0 if trackers.empty? || roles.empty?

        transitions = sanitize_transitions(transitions)
        return 0 if transitions.empty?

        skipped = 0
        WorkflowTransition.transaction do
          pairs = writable_pairs(project_id, trackers, roles, ProjectWorkflowScope::TRANSITIONS)
          skipped = (trackers.size * roles.size) - pairs.size
          next if pairs.empty?

          write_pairs(project_id, pairs, transitions)
        end
        # The rules have changed, so anything cached from them is now wrong.
        Resolver.reset_cache!
        skipped
      end

      def self.write_pairs(project_id, pairs, transitions)
        if project_id
          ScopeWriter.touch_scopes(
            project_ids: [project_id],
            tracker_ids: pairs.map { |tracker, _role| tracker.id }.uniq,
            role_ids: pairs.map { |_tracker, role| role.id }.uniq,
            rule_type: ProjectWorkflowScope::TRANSITIONS
          )
        end

        scope = WorkflowTransition.where(project_id: project_id).where(pair_predicate(pairs))
        # Read before either delete: a cell whose author column was submitted
        # while its assignee column said "no change" has to keep the assignee
        # flag the row already carried, exactly as core's row-by-row update does.
        existing = existing_flag_rows(scope, transitions)
        delete_always_rows(scope, transitions)
        delete_flag_rows(scope, transitions)
        insert_transition_rows(build_transition_rows(project_id, pairs, transitions, existing))
      end
      private_class_method :write_pairs

      # INV-2: the rows are written with insert_all, which runs no validations,
      # so this whitelist *is* the validation. It restores core's
      # validates_presence_of :new_status, which the plugin's routing of
      # replace_transitions would otherwise have removed from the generic write
      # path as well, and rejects rule names and cell values the matrix cannot
      # produce.
      #
      # An entry that fails the whitelist is dropped before the delete, not
      # only before the insert, so an unacceptable value changes nothing rather
      # than removing the transition it names.
      def self.sanitize_transitions(transitions)
        status_ids = valid_status_ids

        to_hash(transitions).each_with_object({}) do |(old_status_id, by_new_status), sanitized|
          next unless by_new_status.respond_to?(:each)
          next unless old_status_id.to_s == NEW_ISSUE_STATUS_ID || status_ids.include?(old_status_id.to_s)

          row = sanitize_transition_row(by_new_status, status_ids)
          sanitized[old_status_id] = row unless row.empty?
        end
      end
      private_class_method :sanitize_transitions

      def self.sanitize_transition_row(by_new_status, status_ids)
        by_new_status.each_with_object({}) do |(new_status_id, transition_by_rule), row|
          next unless transition_by_rule.respond_to?(:each)
          next unless status_ids.include?(new_status_id.to_s)

          # The rule name is normalised to a String here so that everything
          # below can ask `key?(ALWAYS)` and get a reliable answer: which rules
          # were *submitted* is now what decides which rows are deleted, and a
          # symbol key would silently read as "not submitted".
          rules = transition_by_rule.each_with_object({}) do |(rule, value), kept|
            kept[rule.to_s] = value if permitted_cell?(rule, value)
          end
          row[new_status_id] = rules unless rules.empty?
        end
      end
      private_class_method :sanitize_transition_row

      def self.permitted_cell?(rule, value)
        RULES.include?(rule.to_s) && VALUES.include?(value)
      end
      private_class_method :permitted_cell?

      def self.valid_status_ids
        IssueStatus.pluck(:id).to_set(&:to_s)
      end
      private_class_method :valid_status_ids

      def self.to_hash(transitions)
        return {} if transitions.nil?

        if transitions.respond_to?(:to_unsafe_h)
          transitions.to_unsafe_h
        elsif transitions.respond_to?(:to_h)
          transitions.to_h
        else
          transitions
        end
      end
      private_class_method :to_hash

      def self.flags_submitted?(rules)
        rules.key?(AUTHOR) || rules.key?(ASSIGNEE)
      end
      private_class_method :flags_submitted?

      # {[old_status_id, new_status_id, tracker_id, role_id] => [author, assignee]}
      # for the cells whose author or assignee column was submitted.
      #
      # Two rows for one key are a duplicate the table has no constraint against
      # (see WorkflowRule.delete_duplicate_rules!). Their flags are OR-ed rather
      # than one of them being picked, because picking would depend on the order
      # the database returned them -- and OR is what the matrix already shows,
      # since it renders a checked box for either flag.
      def self.existing_flag_rows(scope, transitions)
        pairs = submitted_pairs(transitions) { |rules| flags_submitted?(rules) }
        return {} if pairs.empty?

        table = WorkflowTransition.arel_table
        rows = scope.where(status_pair_predicate(pairs))
                    .where(table[:author].eq(true).or(table[:assignee].eq(true)))
                    .pluck(:old_status_id, :new_status_id, :tracker_id, :role_id, :author, :assignee)
        rows.each_with_object({}) do |(old_status_id, new_status_id, tracker_id, role_id, author, assignee), map|
          key = [old_status_id, new_status_id, tracker_id, role_id]
          held = map[key] || [false, false]
          map[key] = [held[0] || author, held[1] || assignee]
        end
      end
      private_class_method :existing_flag_rows

      # The (old status, new status) pairs whose cell satisfies the block.
      def self.submitted_pairs(transitions)
        transitions.flat_map do |old_status_id, by_new_status|
          by_new_status.filter_map do |new_status_id, rules|
            [old_status_id.to_i, new_status_id.to_i] if yield(rules)
          end
        end
      end
      private_class_method :submitted_pairs

      def self.status_pair_predicate(pairs)
        table = WorkflowTransition.arel_table
        conditions = pairs.group_by(&:first).map do |old_status_id, group|
          table[:old_status_id].eq(old_status_id)
                               .and(table[:new_status_id].in(group.map(&:last)))
        end
        conditions.reduce { |memo, condition| memo.or(condition) }
      end
      private_class_method :status_pair_predicate

      def self.build_transition_rows(project_id, pairs, transitions, existing)
        rows = []
        transitions.each do |old_status_id, transitions_by_new_status|
          old_status_id = old_status_id.to_i
          transitions_by_new_status.each do |new_status_id, rules|
            new_status_id = new_status_id.to_i
            pairs.each do |tracker, role|
              key = { old_status_id: old_status_id, new_status_id: new_status_id,
                      tracker_id: tracker.id, role_id: role.id, project_id: project_id }
              rows.concat(rows_for_cell(key, rules, existing))
            end
          end
        end
        rows
      end

      # The two rows one cell can produce, from the rules that were actually
      # submitted for it. A rule the operator left at "no change" is not in
      # +rules+ at all, and the flag it governs is then taken from the row that
      # is already stored rather than defaulted to false -- which is what turned
      # "leave this alone" into "remove it".
      def self.rows_for_cell(key, rules, existing)
        rows = []
        rows << transition_row(**key, author: false, assignee: false) if transition_enabled?(rules[ALWAYS])
        return rows unless flags_submitted?(rules)

        held = existing[[key[:old_status_id], key[:new_status_id], key[:tracker_id], key[:role_id]]] ||
               [false, false]
        author = rules.key?(AUTHOR) ? transition_enabled?(rules[AUTHOR]) : held[0]
        assignee = rules.key?(ASSIGNEE) ? transition_enabled?(rules[ASSIGNEE]) : held[1]
        rows << transition_row(**key, author: author, assignee: assignee) if author || assignee
        rows
      end
      private_class_method :rows_for_cell

      # Keyword arguments rather than seven positional ones, the last two of
      # which are booleans: `transition_row(a, b, c, d, e, false, false)` puts
      # the author and assignee flags in an order nothing at the call site
      # names, and getting them the wrong way round writes a workflow that
      # permits the opposite of what was asked for.
      def self.transition_row(old_status_id:, new_status_id:, tracker_id:, role_id:, project_id:,
                              author:, assignee:)
        {
          old_status_id: old_status_id,
          new_status_id: new_status_id,
          tracker_id: tracker_id,
          role_id: role_id,
          project_id: project_id,
          author: author,
          assignee: assignee,
          type: 'WorkflowTransition'
        }
      end

      # The unconditional row, and only for the cells whose "always" column was
      # actually submitted. One cell is three controls over two rows, and each
      # of the three can independently arrive as "no change"; deleting on the
      # (old status, new status) key alone therefore removed rows nobody had
      # asked about.
      def self.delete_always_rows(scope, transitions)
        pairs = submitted_pairs(transitions) { |rules| rules.key?(ALWAYS) }
        return if pairs.empty?

        table = WorkflowTransition.arel_table
        scope.where(status_pair_predicate(pairs))
             .where(table[:author].eq(false).and(table[:assignee].eq(false)))
             .delete_all
      end
      private_class_method :delete_always_rows

      # The author/assignee row, for the cells whose author or assignee column
      # was submitted. It is rewritten rather than updated in place, and
      # #rows_for_cell carries whichever of the two flags was not submitted.
      def self.delete_flag_rows(scope, transitions)
        pairs = submitted_pairs(transitions) { |rules| flags_submitted?(rules) }
        return if pairs.empty?

        table = WorkflowTransition.arel_table
        scope.where(status_pair_predicate(pairs))
             .where(table[:author].eq(true).or(table[:assignee].eq(true)))
             .delete_all
      end
      private_class_method :delete_flag_rows

      def self.insert_transition_rows(rows)
        return if rows.empty?

        rows.each_slice(1000) do |slice|
          WorkflowTransition.insert_all(slice)
        end
      end

      def self.transition_enabled?(value)
        ['1', true].include?(value)
      end
    end
  end
end
