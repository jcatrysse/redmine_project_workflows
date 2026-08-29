# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Everything a downgrade throws away, written to one file.
    #
    # WP16. `VERSION=0` is **not** the reverse of an upgrade, and the uninstall
    # procedure has to open with that sentence: migration 001's `down` deletes
    # every workflow rule that names a project before it drops the column,
    # deliberately, because dropping the column with those rows still in the
    # table would turn every project's rules into rules of the workflow every
    # project shares. An own *empty* decision does not survive either -- the
    # scope row is the only place it was ever recorded, and the scope table goes
    # too. So a downgrade discards every project workflow and keeps the generic
    # one, which is exactly the population this file holds.
    #
    # The generic workflow is **not** in it. Nothing this plugin's migrations do
    # touches a `project_id IS NULL` row, so backing it up here would be backing
    # up something that is not at risk -- and restoring it would be a generic
    # write, which is the one thing INV-1 says a project restore must never be.
    #
    # The format is JSON rather than YAML for one reason: reading a backup is
    # `JSON.parse`, which builds no objects, where `YAML.load` of a file an
    # operator was told to keep somewhere safe is a much larger promise.
    class WorkflowBackup
      FORMAT = 'redmine_project_workflows.backup'
      # Bumped when the *meaning* of a field changes. WorkflowRestore accepts
      # any version up to this one, so a file written by an older plugin still
      # restores; a file written by a newer one is refused rather than guessed
      # at.
      FORMAT_VERSION = 1

      # The transitions matrix's "new issue" column is stored as old_status_id
      # 0, which is not an IssueStatus and therefore has no name to look up.
      NEW_ISSUE_STATUS_ID = 0

      class Error < StandardError; end

      # **Both reads in one snapshot**, which is WP17 and finding F02 of
      # 2026-08-29-claude-revalidation. A project workflow is two rows in two
      # tables -- the decision in `project_workflow_scopes`, the rules in
      # `workflows` -- and reading them one after the other on a live
      # installation could catch a save in between, writing a file holding a
      # state that never existed. Both directions are damaging, and the second
      # silently:
      #
      #   * scopes read first, rules read after somebody enabled a project's own
      #     workflow: rules with no decision behind them. The restore reports
      #     them as orphans and drops them, so the file is merely incomplete.
      #   * scopes read first, rules read after somebody returned a project to
      #     inheritance: a decision with no rules under it, which is not an
      #     absence but an own EMPTY workflow -- a project that permits no
      #     status change at all (INV-3). Restoring that file *creates* that
      #     state on a project that never chose it.
      #
      # A backup is the thing an operator takes before a migration, on a
      # production installation nobody has been asked to stop using. So it takes
      # the strongest isolation the adapter offers rather than the default:
      # PostgreSQL's READ COMMITTED would let the second query see a commit the
      # first did not, which is exactly the window above. MySQL and MariaDB
      # default to REPEATABLE READ already and asking for it costs nothing;
      # SQLite has no isolation levels to set and gives one reader one
      # consistent view anyway.
      def self.document
        scopes, rules = snapshot { [scope_rows, rule_rows] }
        {
          'format' => FORMAT,
          'format_version' => FORMAT_VERSION,
          'plugin_version' => plugin_version,
          'redmine_version' => Compatibility.host_version,
          'exported_at' => Time.now.utc.iso8601,
          'names' => names_for(scopes, rules),
          'scopes' => scopes,
          'rules' => rules
        }
      end

      # Joins a transaction that is already open rather than nesting inside one:
      # an isolation level can only be set by the transaction that begins, and
      # a caller who has already opened one -- a spec under transactional
      # fixtures, an operator's own wrapper -- has given the two reads their
      # snapshot by opening it. Asking anyway would raise
      # ActiveRecord::TransactionIsolationError and turn a backup into an
      # exception, which is the last thing this file should do.
      #
      # And falls back to a plain transaction on an adapter that will not give
      # the level. `supports_transaction_isolation?` is not the question to ask
      # -- SQLite answers **true** to it and then refuses every level but
      # `read_uncommitted` -- so the check that reads like the careful one is
      # the one that raises. Asking and catching the refusal is the only form
      # that is right for an adapter nobody has met yet.
      #
      # A **retry**, deliberately, and not a resume. Rails opens a transaction
      # lazily: the BEGIN is deferred to the first statement inside the block,
      # so the refusal can arrive either from the `transaction` call itself or
      # from the middle of the block, and which one depends on the Rails version
      # as much as on the adapter. Measured, not assumed: on Rails 6.1 with
      # SQLite it arrives from inside the block, so a fallback that only covered
      # the first case would re-raise -- which is what `dev/check-uninstall.sh`
      # caught before this comment was written. Running the block twice is safe
      # because it is two SELECTs and nothing else; anything that writes must
      # not be put inside it.
      def self.snapshot(&)
        return yield if ProjectWorkflowScope.connection.transaction_open?

        ActiveRecord::Base.transaction(isolation: :repeatable_read, &)
      rescue ActiveRecord::TransactionIsolationError
        ActiveRecord::Base.transaction(&)
      end
      private_class_method :snapshot

      # Refuses to overwrite an existing file unless asked twice. A backup is
      # written by an operator who is about to destroy the thing it holds, and
      # the second-most-likely mistake after not taking one at all is writing
      # the new one over the last good one.
      # +document+ so that a caller which has already built one -- the uninstall
      # task, which counts what is about to be lost before it asks -- writes the
      # file it showed the operator rather than a second export taken a moment
      # later.
      def self.write(path, document: nil, force: false)
        raise Error, "#{path} already exists; pass FORCE=1 to overwrite it" if File.exist?(path) && !force

        written = document || self.document
        File.write(path, "#{JSON.pretty_generate(written)}\n")
        written
      end

      def self.read(path)
        raise Error, "#{path} does not exist" unless File.exist?(path)

        validate(JSON.parse(File.read(path)))
      rescue JSON::ParserError => e
        raise Error, "#{path} is not a readable backup: #{e.message}"
      end

      # What a restore may rely on: the two keys it dispatches on, and both
      # collections present and of the right shape. Everything below that --
      # a project that has since been deleted, a status that has, a rule the
      # whitelist refuses -- is the restore's business and is reported rather
      # than raised, because a backup outlives the installation it came from.
      def self.validate(document)
        raise Error, 'not a backup file: no format marker' unless document.is_a?(Hash) && document['format'] == FORMAT

        version = document['format_version']
        unless version.is_a?(Integer) && version.between?(1, FORMAT_VERSION)
          raise Error, "backup format version #{version.inspect} is not one this plugin can read " \
                       "(it reads 1..#{FORMAT_VERSION})"
        end
        %w[scopes rules].each do |key|
          raise Error, "backup file has no #{key}" unless document[key].is_a?(Array)
        end
        document
      end

      # INV-4: `project_id IS NOT NULL` is the predicate, and it is the whole
      # population this file is about.
      #
      # Plucked rather than instantiated. An installation can hold one of these
      # per project, tracker and role, and none of the eight columns needs a
      # model behind it.
      def self.scope_rows
        ProjectWorkflowScope.where.not(project_id: nil)
                            .order(:project_id, :tracker_id, :role_id, :rule_type)
                            .pluck(:project_id, :tracker_id, :role_id, :rule_type,
                                   :created_by_id, :created_at, :updated_by_id, :updated_at)
                            .map { |row| scope_row(row) }
      end
      private_class_method :scope_rows

      # As with #rule_row, the row arrives as the array above plucked, in that
      # order, rather than as eight positional arguments.
      def self.scope_row(row)
        project_id, tracker_id, role_id, rule_type,
          created_by_id, created_at, updated_by_id, updated_at = row
        {
          'project_id' => project_id,
          'tracker_id' => tracker_id,
          'role_id' => role_id,
          'rule_type' => rule_type,
          'created_by_id' => created_by_id,
          'created_at' => created_at&.utc&.iso8601,
          'updated_by_id' => updated_by_id,
          'updated_at' => updated_at&.utc&.iso8601
        }
      end
      private_class_method :scope_row

      # Ordered by every column that identifies a rule, so that two exports of
      # the same database are the same file and a diff of two backups is a diff
      # of two workflows. `id` last, to settle the duplicate rows a database
      # from before 0.1.6 can still carry.
      def self.rule_rows
        WorkflowRule.where.not(project_id: nil)
                    .order(:project_id, :tracker_id, :role_id, :type, :old_status_id,
                           :new_status_id, :field_name, :id)
                    .pluck(:type, :project_id, :tracker_id, :role_id, :old_status_id,
                           :new_status_id, :field_name, :rule, :author, :assignee)
                    .map { |row| rule_row(row) }
      end
      private_class_method :rule_rows

      # Only the columns the rule's own type gives a meaning to. A transition
      # carries no field name and a permission carries no author flag; writing
      # the nulls out would make the file half again as long and suggest the
      # restore had something to do with them.
      # The row arrives as the array #rule_rows plucked, in that order, rather
      # than as ten positional arguments: ten of them in an order nothing at the
      # call site names is how two status columns come to be swapped.
      def self.rule_row(row)
        type, project_id, tracker_id, role_id, old_status_id,
          new_status_id, field_name, rule, author, assignee = row
        common = { 'type' => type, 'project_id' => project_id, 'tracker_id' => tracker_id,
                   'role_id' => role_id, 'old_status_id' => old_status_id }
        case type
        when 'WorkflowTransition'
          common.merge('new_status_id' => new_status_id, 'author' => !!author, 'assignee' => !!assignee)
        else
          common.merge('field_name' => field_name, 'rule' => rule)
        end
      end
      private_class_method :rule_row

      # Names, so that a backup can be read by the person who has to decide
      # whether to restore it. Nothing in the restore matches on them: ids are
      # what a rule is made of, and a project that has been renamed is still the
      # project the rules belong to.
      def self.names_for(scopes, rules)
        rows = scopes + rules
        {
          'projects' => name_map(Project, rows.map { |row| row['project_id'] }),
          'trackers' => name_map(Tracker, rows.map { |row| row['tracker_id'] }),
          'roles' => name_map(Role, rows.map { |row| row['role_id'] }),
          'statuses' => name_map(
            IssueStatus,
            rules.flat_map { |row| [row['old_status_id'], row['new_status_id']] } - [NEW_ISSUE_STATUS_ID]
          )
        }
      end
      private_class_method :names_for

      def self.name_map(model, ids)
        ids = ids.compact.uniq
        return {} if ids.empty?

        model.where(id: ids).pluck(:id, :name).to_h { |id, name| [id.to_s, name] }
      end
      private_class_method :name_map

      def self.plugin_version
        Redmine::Plugin.find(:redmine_project_workflows).version
      rescue Redmine::PluginNotFound
        nil
      end
      private_class_method :plugin_version
    end
  end
end
