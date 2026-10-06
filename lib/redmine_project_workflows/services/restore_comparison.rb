# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Whether a project workflow the restore is about to leave alone is already
    # the one the backup holds.
    #
    # WP17. `OVERWRITE=1` is the only decision a restore cannot take on the
    # operator's behalf, and until this existed the report gave them nothing to
    # take it with: "12 left alone" read identically whether those twelve were
    # byte-for-byte what the file holds or twelve projects' worth of edits the
    # restore was about to leave in place.
    #
    # Compared as **sets of what a rule permits**, not as rows. The writers take
    # a matrix and a matrix has one cell, so the duplicate rows a database from
    # before 0.1.6 can carry collapse on the way in; counting a duplicate as a
    # difference would report a change that a restore would not make.
    class RestoreComparison
      # The pluck list, named once. A row read positionally in one place and
      # written positionally in another is how two status columns come to be
      # swapped, so the rows become hashes at the boundary -- which also lets a
      # backup row and a database row share one signature method, the thing that
      # makes this comparison worth trusting.
      COLUMNS = %i[type project_id tracker_id role_id old_status_id
                   new_status_id field_name rule author assignee].freeze

      # +skipped+ is [[key, backup_rows], ...]. One query for all of them, not
      # one each: the point of the number is that an operator can act on it, and
      # a report costing a query per skipped project on a two-thousand-project
      # installation is a report nobody waits for.
      def self.differing(skipped)
        return 0 if skipped.empty?

        current = current_signatures(skipped.map(&:first))
        skipped.count { |key, rows| current[key] != backup_signatures(key, rows) }
      end

      # A combination with a decision and no rules under it -- an own EMPTY
      # workflow -- has no rows here and so gets the empty set, which is exactly
      # right: it differs from a backup that holds rules and matches one that
      # does not.
      def self.current_signatures(keys)
        wanted = keys.to_set
        signatures = Hash.new { |hash, key| hash[key] = Set.new }
        current_rows(keys).each do |row|
          key = row_key(row)
          signatures[key] << signature_of(row, key.last) if wanted.include?(key)
        end
        signatures
      end
      private_class_method :current_signatures

      # INV-4: the predicate names the projects, so this reads the project
      # population and nothing else. The relation is the cross product of the
      # ids, which is wider than the combinations themselves; +wanted+ above is
      # what makes the answer exact.
      def self.current_rows(keys)
        WorkflowRule.where(project_id: keys.map(&:first).uniq,
                           tracker_id: keys.map { |key| key[1] }.uniq,
                           role_id: keys.map { |key| key[2] }.uniq)
                    .pluck(*COLUMNS).map { |row| COLUMNS.zip(row).to_h }
      end
      private_class_method :current_rows

      # A rule type this plugin does not know -- a subclass some neighbour
      # registered -- becomes a key nothing wants, which is the right answer:
      # it is not part of any combination this backup records a decision for.
      def self.row_key(row)
        [row[:project_id], row[:tracker_id], row[:role_id], rule_type_for(row[:type])]
      end
      private_class_method :row_key

      def self.rule_type_for(type)
        ProjectWorkflowScope.rule_type_for(type)
      rescue ArgumentError
        nil
      end
      private_class_method :rule_type_for

      def self.backup_signatures(key, rows)
        rows.to_set { |row| signature_of(row.transform_keys(&:to_sym), key.last) }
      end
      private_class_method :backup_signatures

      # `== true` rather than `!!`: both sides can carry nil -- a database column
      # that was never set, a backup key that is absent -- and both mean the flag
      # is off.
      def self.signature_of(row, rule_type)
        if rule_type == ProjectWorkflowScope::TRANSITIONS
          [row[:old_status_id], row[:new_status_id], row[:author] == true, row[:assignee] == true]
        else
          [row[:old_status_id], row[:field_name], row[:rule]]
        end
      end
      private_class_method :signature_of
    end
  end
end
