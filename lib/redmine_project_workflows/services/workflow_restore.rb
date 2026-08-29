# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Puts a WorkflowBackup back, through the writers rather than around them.
    #
    # WP16. Every rule this writes goes through TransitionWriter or
    # PermissionWriter, which is INV-2: a backup file is data of unknown age
    # from outside the application, so the whitelist that stands between a
    # request and the `workflows` table has to stand between a file and it too.
    # A status, a tracker or a custom field deleted since the export is refused
    # there and counted here, rather than being written back as a row naming
    # nothing.
    #
    # It restores three states and keeps them apart (INV-3): a combination with
    # rules, a combination with an own *empty* workflow -- a scope and no rules,
    # which is the state the scope table exists to make expressible -- and a
    # combination the backup does not mention, which stays inheriting.
    #
    # **Not a byte-for-byte restore, in one direction only.** Duplicate rows,
    # which a database from before 0.1.6 can carry, come back as one row: the
    # payload the writers take is a matrix, and a matrix has one cell. That is
    # the same repair `redmine_project_workflows:deduplicate_workflow_rules`
    # performs, and it cannot change what a workflow permits.
    #
    # **Its cost is one writer call per combination**, by construction: a writer
    # call covers one project, and the rules of two projects are not the same
    # rules. The scope creation is grouped -- one call per (tracker, role, rule
    # type), whatever the number of projects -- because that one takes a lock.
    # This is a maintenance task run once, not a request path.
    class WorkflowRestore
      # What a restore did, in the terms an operator has to check it against.
      Report = Struct.new(:scopes, :rules, :rejected, :skipped_existing,
                          :skipped_missing, :orphan_rules, keyword_init: true) do
        def lines
          [
            "#{scopes} project #{'workflow'.pluralize(scopes)} restored, " \
            "#{rules} #{'rule'.pluralize(rules)} read from the backup",
            "#{rejected} #{'value'.pluralize(rejected)} refused by validation and not written",
            "#{skipped_existing} left alone: the project already has a workflow there",
            "#{orphan_rules} #{'rule'.pluralize(orphan_rules)} not restored: " \
            'no recorded decision in the backup names them',
            *skipped_missing
          ]
        end
      end

      # The three things a rule is made of, as they are *now*, plus the users
      # its audit columns name and the combinations that already have a
      # decision. Loaded once: asking per combination would be six queries per
      # row of a file that can hold one per project, tracker and role on the
      # installation.
      Referents = Struct.new(:projects, :trackers, :roles, :users, :scoped) do
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

      # +overwrite+ decides the one case a restore cannot guess at: the
      # combination already has a scope. The default leaves it alone, because
      # the likeliest reason for one to be there is that somebody has since made
      # a decision of their own -- and a restore is usually run on an
      # installation whose plugin data was just thrown away, where there is
      # nothing to leave alone and the default costs nothing.
      def self.call(document, overwrite: false, user: User.current)
        document = WorkflowBackup.validate(document)
        rules = group_rules(document['rules'])
        referents = load_referents(document)
        report = Report.new(scopes: 0, rules: 0, rejected: 0, skipped_existing: 0,
                            skipped_missing: [], orphan_rules: 0)

        restorable = select_restorable(document['scopes'], rules, referents, overwrite, report)
        prepare(restorable.map(&:first), referents, user)
        restorable.each { |key, scope, rows| write_one(key, scope, rows, referents, report) }
        report.orphan_rules = rules.values.sum(&:size)
        report
      end

      # Every combination the backup records a decision for is taken out of the
      # rule index here, skipped or not: an orphan is a rule the backup names
      # with no decision behind it, and a rule left behind by a combination this
      # restore chose not to touch is not that.
      def self.select_restorable(scopes, rules, referents, overwrite, report)
        scopes.filter_map do |scope|
          key = combination_key(scope)
          rows = rules.delete(key) || []
          missing = referents.missing(key)
          if missing
            report.skipped_missing << missing
            next
          end
          if referents.scoped?(key) && !overwrite
            report.skipped_existing += 1
            next
          end

          [key, scope, rows]
        end
      end
      private_class_method :select_restorable

      # The scope first, because the writers refuse to write project rules for a
      # combination that has none -- that refusal is what stops a plain Save from
      # turning an inheriting project into one with an own workflow, and a
      # restore has to go the long way round it rather than through it.
      #
      # `copy_generic: false`: a restore replaces what the backup holds and
      # nothing else. Copying the generic rules in first and writing over them
      # would leave, for every cell the backup does not mention, whatever the
      # generic workflow says today -- which is the additive override INV-5 says
      # does not exist.
      def self.prepare(keys, referents, user)
        existing, fresh = keys.partition { |key| referents.scoped?(key) }
        by_pair(fresh) do |selection|
          ScopeWriter.enable(**selection, copy_generic: false, user: user)
        end
        # Overwriting: the scope stays and its rules go, which is INV-3's third
        # action. Deleting the scope and enabling it again would move
        # `created_by_id`, and the backup is about to put the original back.
        by_pair(existing) do |selection|
          ScopeWriter.clear_rules(**selection, user: user)
        end
      end
      private_class_method :prepare

      # One call per (tracker, role, rule type) rather than one per combination.
      # ScopeWriter.enable takes the coordination rows for the pairs it is given,
      # so a restore of five hundred projects takes one lock per pair instead of
      # five hundred; and with one tracker and one role the cross product it
      # creates over the project list is exactly the combinations asked for.
      def self.by_pair(keys)
        keys.group_by { |(_project_id, tracker_id, role_id, rule_type)| [tracker_id, role_id, rule_type] }
            .each do |(tracker_id, role_id, rule_type), group|
          yield(project_ids: group.map(&:first), tracker_ids: [tracker_id],
                role_ids: [role_id], rule_type: rule_type)
        end
      end
      private_class_method :by_pair

      def self.write_one(key, scope, rows, referents, report)
        report.rejected += write_rules(key, rows, referents)
        report.scopes += 1
        report.rules += rows.size
        stamp_audit(key, scope, referents)
      end
      private_class_method :write_one

      # [project_id, tracker_id, role_id, rule_type] -- the unit a scope is a
      # decision about, and the unit a writer call covers.
      def self.combination_key(row)
        rule_type = row['rule_type'] || rule_type_for(row['type'])
        [row['project_id'], row['tracker_id'], row['role_id'], rule_type]
      end
      private_class_method :combination_key

      # An unreadable `type` becomes a key nothing matches, so the rows carrying
      # it are reported as orphans rather than raising: a backup is a file, and
      # a corrupt line in it must not stop the rest of an installation's
      # workflows from coming back.
      def self.rule_type_for(type)
        ProjectWorkflowScope.rule_type_for(type)
      rescue ArgumentError
        type
      end
      private_class_method :rule_type_for

      def self.group_rules(rules)
        rules.group_by { |row| combination_key(row) }
      end
      private_class_method :group_rules

      def self.load_referents(document)
        rows = document['scopes'] + document['rules']
        keys = document['scopes'].map { |scope| combination_key(scope) }
        Referents.new(
          id_set(Project, rows.map { |row| row['project_id'] }),
          by_id(Tracker, rows.map { |row| row['tracker_id'] }),
          by_id(Role, rows.map { |row| row['role_id'] }),
          id_set(User, document['scopes'].flat_map { |row| [row['created_by_id'], row['updated_by_id']] }),
          existing_scope_keys(keys)
        )
      end
      private_class_method :load_referents

      def self.id_set(model, ids)
        ids = ids.compact.uniq
        return Set.new if ids.empty?

        model.where(id: ids).pluck(:id).to_set
      end
      private_class_method :id_set

      def self.by_id(model, ids)
        ids = ids.compact.uniq
        return {} if ids.empty?

        model.where(id: ids).index_by(&:id)
      end
      private_class_method :by_id

      # One query for the whole file. The relation is the cross product of the
      # ids the backup names, which is wider than the combinations themselves;
      # the intersection with +keys+ below is what makes the answer exact.
      def self.existing_scope_keys(keys)
        return Set.new if keys.empty?

        wanted = keys.to_set
        ProjectWorkflowScope.where(project_id: keys.map(&:first).uniq,
                                   tracker_id: keys.map { |key| key[1] }.uniq,
                                   role_id: keys.map { |key| key[2] }.uniq)
                            .pluck(:project_id, :tracker_id, :role_id, :rule_type)
                            .select { |key| wanted.include?(key) }.to_set
      end
      private_class_method :existing_scope_keys

      # Returns what the whitelist refused, which is the number that matters:
      # everything else about this call is already known from the backup.
      def self.write_rules(key, rows, referents)
        return 0 if rows.empty?

        project_id, tracker_id, role_id, rule_type = key
        trackers = [referents.trackers.fetch(tracker_id)]
        roles = [referents.roles.fetch(role_id)]
        if rule_type == ProjectWorkflowScope::TRANSITIONS
          TransitionWriter.replace_transitions_for_project_id(
            project_id, trackers, roles, transition_payload(rows)
          ).rejected
        else
          PermissionWriter.replace_permissions_for_project_id(
            project_id, trackers, roles, permission_payload(rows)
          ).rejected
        end
      end
      private_class_method :write_rules

      # {old_status_id => {new_status_id => {rule => '1'}}}, the shape the matrix
      # submits. One cell is two rows -- the unconditional one, and the one
      # carrying whichever of the author and assignee flags apply -- and both can
      # be present, so the cell is built up rather than assigned.
      def self.transition_payload(rows)
        rows.each_with_object({}) do |row, payload|
          cell = ((payload[row['old_status_id'].to_s] ||= {})[row['new_status_id'].to_s] ||= {})
          if row['author'] || row['assignee']
            cell[TransitionWriter::AUTHOR] = '1' if row['author']
            cell[TransitionWriter::ASSIGNEE] = '1' if row['assignee']
          else
            cell[TransitionWriter::ALWAYS] = '1'
          end
        end
      end
      private_class_method :transition_payload

      # {old_status_id => {field_name => rule}}.
      def self.permission_payload(rows)
        rows.each_with_object({}) do |row, payload|
          (payload[row['old_status_id'].to_s] ||= {})[row['field_name'].to_s] = row['rule']
        end
      end
      private_class_method :permission_payload

      # The audit trail is half of what the backup is for: `created_by_id` says
      # who decided this project runs its own workflow and when, and a restore
      # that stamped the operator running the rake task over it would answer that
      # question wrongly for every project at once. A user deleted since the
      # export leaves the column null, which is what the column already means --
      # `ProjectWorkflowScope.created_by` is optional for exactly this.
      def self.stamp_audit(key, scope, referents)
        project_id, tracker_id, role_id, rule_type = key
        ProjectWorkflowScope.where(project_id: project_id, tracker_id: tracker_id,
                                   role_id: role_id, rule_type: rule_type)
                            .update_all(audit_columns(scope, referents)) # rubocop:disable Rails/SkipsModelValidations
      end
      private_class_method :stamp_audit

      def self.audit_columns(scope, referents)
        now = Time.now.utc
        {
          created_by_id: referents.user_id(scope['created_by_id']),
          updated_by_id: referents.user_id(scope['updated_by_id']),
          created_at: scope['created_at'] || now,
          updated_at: scope['updated_at'] || now
        }
      end
      private_class_method :audit_columns
    end
  end
end
