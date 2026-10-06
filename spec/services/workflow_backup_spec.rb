# frozen_string_literal: true

require_relative '../spec_helper'
require 'tmpdir'
require 'fileutils'

# WP16. The backup exists because a downgrade is not the reverse of an upgrade:
# `VERSION=0` deletes every workflow rule that names a project and drops the
# table that records which projects decided to have one. This file asserts the
# round trip that makes that survivable -- export, throw the rows away, restore
# -- and the three things it must keep apart while doing it (INV-3).
describe RedmineProjectWorkflows::Services::WorkflowBackup do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:restore) { RedmineProjectWorkflows::Services::WorkflowRestore }
  let(:project) { projects(:projects_001) }
  let(:other) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:permissions) { ProjectWorkflowScope::PERMISSIONS }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def transition(target, from: s1, to: s2, author: false, assignee: false)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: target&.id,
                               old_status_id: from.id, new_status_id: to.id,
                               author: author, assignee: assignee)
  end

  def permission(target, field: 'due_date', rule: 'required', status: s1)
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: target&.id,
                               old_status_id: status.id, field_name: field, rule: rule)
  end

  # What a downgrade does, without running one: the rows a project workflow is
  # made of, gone. The scope table survives here because dropping it inside an
  # example is not something a test database recovers from -- the migration
  # rehearsal in dev/check-uninstall.sh is where the real drop is exercised.
  def discard_project_workflows
    WorkflowRule.where.not(project_id: nil).delete_all
    ProjectWorkflowScope.where.not(project_id: nil).delete_all
  end

  def project_rules
    WorkflowRule.where.not(project_id: nil)
                .pluck(:type, :project_id, :tracker_id, :role_id, :old_status_id,
                       :new_status_id, :field_name, :rule, :author, :assignee).sort_by(&:to_s)
  end

  def scope_rows
    ProjectWorkflowScope.where.not(project_id: nil)
                        .pluck(:project_id, :tracker_id, :role_id, :rule_type).sort
  end

  describe '.document' do
    it 'holds every project rule and no generic one' do
      transition(nil)
      transition(project)
      give_own_workflow(project, tracker, role)

      document = described_class.document

      expect(document['format']).to eq(described_class::FORMAT)
      expect(document['rules'].size).to eq(1)
      expect(document['rules'].first).to include('project_id' => project.id, 'type' => 'WorkflowTransition')
      expect(document['scopes'].size).to eq(1)
    end

    # The names are for the operator who has to decide whether to restore a
    # file, and for nothing else: ids are what a rule is made of.
    it 'names the projects, trackers, roles and statuses it refers to' do
      transition(project)
      give_own_workflow(project, tracker, role)

      names = described_class.document['names']

      expect(names['projects']).to eq(project.id.to_s => project.name)
      expect(names['trackers']).to eq(tracker.id.to_s => tracker.name)
      expect(names['roles']).to eq(role.id.to_s => role.name)
      expect(names['statuses']).to include(s1.id.to_s => s1.name, s2.id.to_s => s2.name)
    end

    # old_status_id 0 is the "new issue" column of the transitions matrix and is
    # not an IssueStatus at all, so there is no name to look up for it.
    it 'looks up no name for the new-issue pseudo status' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: 0, new_status_id: s2.id)
      give_own_workflow(project, tracker, role)

      expect(described_class.document['names']['statuses'].keys).to contain_exactly(s2.id.to_s)
    end

    it 'writes the same file twice for the same database' do
      transition(project, from: s2, to: s1)
      transition(project)
      give_own_workflow(project, tracker, role)

      expect(described_class.document['rules']).to eq(described_class.document['rules'])
    end
  end

  describe '.write and .read' do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, 'backup.json') }

    after { FileUtils.remove_entry(dir) }

    it 'writes a file .read accepts' do
      transition(project)
      give_own_workflow(project, tracker, role)

      described_class.write(path)

      expect(described_class.read(path)['rules'].size).to eq(1)
    end

    it 'refuses to overwrite the last good backup unless asked twice' do
      described_class.write(path)

      expect { described_class.write(path) }
        .to raise_error(described_class::Error, /already exists/)
      expect { described_class.write(path, force: true) }.not_to raise_error
    end

    it 'refuses a file that is not a backup' do
      File.write(path, '{"format":"something else"}')

      expect { described_class.read(path) }
        .to raise_error(described_class::Error, /no format marker/)
    end

    it 'refuses a format version it cannot read' do
      File.write(path, JSON.generate('format' => described_class::FORMAT,
                                     'format_version' => described_class::FORMAT_VERSION + 1,
                                     'scopes' => [], 'rules' => []))

      expect { described_class.read(path) }
        .to raise_error(described_class::Error, /format version/)
    end

    it 'refuses a file that is not JSON at all' do
      File.write(path, 'not json')

      expect { described_class.read(path) }
        .to raise_error(described_class::Error, /not a readable backup/)
    end

    # WP19, finding F04 of 2026-08-29-claude-revalidation. The file names every
    # project, tracker, role and status on the installation, and the README says
    # to keep it somewhere that is not world-readable; before this it was written
    # at whatever the umask allowed, measured as 0644.
    it 'writes the file readable only by the operator who wrote it' do
      transition(project)
      give_own_workflow(project, tracker, role)

      described_class.write(path)

      expect(File.stat(path).mode & 0o777).to eq(0o600)
    end

    # Atomic, so that FORCE=1 cannot destroy the previous backup before the
    # replacement is durable. The temporary file is beside the target because a
    # rename is only atomic within one filesystem, and a backup path is exactly
    # the kind of path that is a mount of its own.
    it 'leaves the previous file untouched when the write fails' do
      give_own_workflow(project, tracker, role)
      described_class.write(path)
      first = File.read(path)
      allow(described_class).to receive(:read).and_raise(described_class::Error, 'simulated')

      expect { described_class.write(path, force: true) }.to raise_error(described_class::Error)

      expect(File.read(path)).to eq(first)
      expect(Dir.children(dir)).to eq([File.basename(path)])
    end

    it 'refuses a file that is not there' do
      expect { described_class.read(path) }.to raise_error(described_class::Error, /does not exist/)
    end
  end

  # WP17, finding F02 of docs/review/findings/2026-08-29-claude-revalidation.md.
  #
  # A project workflow is two rows in two tables: the decision and the rules.
  # Reading them one after the other on an installation nobody has been asked to
  # stop using could catch a save in between and write a file holding a state
  # that never existed -- and one direction of that is silent, because a
  # decision with no rules under it is an own EMPTY workflow, a project that
  # permits no status change at all. Restoring such a file creates that state on
  # a project that never chose it.
  describe 'the snapshot both reads are taken in' do
    # Transactional fixtures *are* an already-open transaction, so this is the
    # case every other example in this file runs under. Asserted once, on its
    # own, because the failure mode is an exception rather than a wrong answer:
    # an isolation level can only be set by the transaction that begins.
    it 'joins a transaction that is already open rather than raising' do
      expect(ActiveRecord::Base.connection).to be_transaction_open

      expect { described_class.document }.not_to raise_error
    end

    it 'asks for repeatable read when it opens one of its own' do
      allow(ProjectWorkflowScope.connection).to receive(:transaction_open?).and_return(false)
      # Stubbed rather than called: asking Rails for an isolation level while
      # the fixture transaction is open is exactly what the guard above avoids,
      # and what is under test here is which level is asked for.
      allow(ActiveRecord::Base).to receive(:transaction) { |**_options, &block| block.call }

      described_class.document

      expect(ActiveRecord::Base).to have_received(:transaction).with(isolation: :repeatable_read)
    end

    # SQLite answers `supports_transaction_isolation?` with **true** and then
    # refuses every level but read_uncommitted, so the fallback cannot be a
    # question asked in advance -- it has to be the refusal, caught. An adapter
    # nobody has met yet gets a backup rather than an exception.
    it 'falls back to a plain transaction when the adapter refuses at BEGIN' do
      give_own_workflow(project, tracker, role)
      transition(project)
      allow(ProjectWorkflowScope.connection).to receive(:transaction_open?).and_return(false)
      allow(ActiveRecord::Base).to receive(:transaction) do |**options, &block|
        raise ActiveRecord::TransactionIsolationError, 'this adapter will not' if options[:isolation]

        block.call
      end

      document = described_class.document

      expect(document['scopes'].size).to eq(1)
      expect(document['rules'].size).to eq(1)
    end

    # The other half, and the one a `began` flag got wrong: Rails opens a
    # transaction lazily, so the BEGIN is deferred to the first statement inside
    # the block and the refusal arrives from the middle of the read rather than
    # from the `transaction` call. Measured on Rails 6.1 with SQLite, by
    # dev/check-uninstall.sh, where it aborted the whole uninstall.
    it 'falls back when the adapter refuses at the first statement inside the block' do
      give_own_workflow(project, tracker, role)
      transition(project)
      allow(ProjectWorkflowScope.connection).to receive(:transaction_open?).and_return(false)
      allow(ActiveRecord::Base).to receive(:transaction) do |**options, &block|
        if options[:isolation]
          described_class.send(:scope_rows)
          raise ActiveRecord::TransactionIsolationError, 'refused at the first statement'
        end
        block.call
      end

      document = described_class.document

      expect(document['scopes'].size).to eq(1)
      expect(document['rules'].size).to eq(1)
    end
  end

  describe 'a save landing between the two reads' do
    # Two connections that can see each other's committed work, which the
    # suite's usual one-transaction-per-example cannot give. The interaction
    # examples above pin which isolation level is asked for; this one is the
    # only thing that shows what asking for it buys, and it is red without it
    # on all three supported adapters -- outside a transaction each of the two
    # reads is its own, whatever the adapter's default isolation.
    if respond_to?(:use_transactional_tests=)
      self.use_transactional_tests = false
    else
      self.use_transactional_fixtures = false
    end

    before do
      skip('SQLite holds one reader against one writer, and is not one of the nine cells') unless supported_adapter?
    end

    after do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
      ProjectWorkflowWriteLock.delete_all
    end

    def in_parallel(&block)
      thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }
      raise 'the second connection never came back' unless thread.join(30)
    end

    it 'cannot write a decision whose rules it read after they were deleted' do
      give_own_workflow(project, tracker, role)
      transition(project)
      main = Thread.current
      target = project.id
      tracker_id = tracker.id
      role_id = role.id

      # The export has read the decisions and is about to read the rules. The
      # other request arrives here and returns the project to inheritance --
      # scope and rules both gone, committed, before the second read runs.
      allow(described_class).to receive(:scope_rows).and_wrap_original do |original|
        rows = original.call
        if Thread.current == main
          in_parallel do
            RedmineProjectWorkflows::Services::ScopeWriter.return_to_inheritance(
              project_ids: [target], tracker_ids: [tracker_id], role_ids: [role_id],
              rule_type: ProjectWorkflowScope::TRANSITIONS
            )
          end
        end
        rows
      end

      document = described_class.document

      # The state as of the first read, whole: the deletion committed after it
      # and is not in this file at all. What must never come back is the scope
      # without its rule, which is a decision this project did not take.
      expect(document['scopes'].size).to eq(1)
      expect(document['rules'].size).to eq(1)
    end
  end

  describe 'the round trip' do
    it 'brings back the rules, the decisions and the generic workflow untouched' do
      transition(nil, from: s2, to: s1)
      give_own_workflow(project, tracker, role)
      transition(project)
      # The same cell again, carrying the flags: one cell of the matrix is two
      # rows, and both have to come back or the restored workflow permits less
      # than the one that was backed up.
      transition(project, author: true, assignee: true)
      transition(project, from: s2, to: s1)
      give_own_workflow(project, tracker, role, permissions)
      permission(project)
      permission(project, field: 'start_date', rule: 'readonly')

      document = described_class.document
      before_rules = project_rules
      before_scopes = scope_rows
      discard_project_workflows

      report = restore.call(document)

      expect(report.scopes).to eq(2)
      expect(project_rules).to eq(before_rules)
      expect(scope_rows).to eq(before_scopes)
      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
    end

    # INV-3: a scope with no rules under it is a decision, not an absence, and
    # it is the state a downgrade destroys most quietly -- the scope row is the
    # only place it was ever recorded.
    it 'brings back an own EMPTY workflow as a decision, not as inheritance' do
      transition(nil)
      give_own_workflow(project, tracker, role)

      document = described_class.document
      discard_project_workflows

      restore.call(document)

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    # The "new issue" column of the transitions matrix is stored as
    # old_status_id 0, which is not an IssueStatus -- and the writers' whitelist
    # has to let exactly that one non-status through, or the column that decides
    # what an issue can be *created* as comes back empty.
    it 'brings back the new-issue column' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: 0, new_status_id: s2.id)

      document = described_class.document
      discard_project_workflows
      report = restore.call(document)

      expect(report.rejected).to eq(0)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:old_status_id, :new_status_id))
        .to eq([[0, s2.id]])
    end

    it 'leaves a project the backup does not mention inheriting' do
      give_own_workflow(project, tracker, role)
      document = described_class.document
      discard_project_workflows

      restore.call(document)

      expect(own_workflow?(other, tracker, role)).to be(false)
    end

    it 'keeps the audit trail rather than stamping whoever ran the restore' do
      author = users(:users_002)
      scope = give_own_workflow(project, tracker, role)
      scope.update!(created_by_id: author.id, updated_by_id: author.id)
      created_at = scope.reload.created_at

      document = described_class.document
      discard_project_workflows
      restore.call(document, user: users(:users_001))

      restored = ProjectWorkflowScope.find_by(project_id: project.id, tracker_id: tracker.id,
                                              role_id: role.id, rule_type: transitions)
      expect(restored.created_by_id).to eq(author.id)
      expect(restored.created_at.utc.to_i).to eq(created_at.utc.to_i)
    end

    it 'leaves the author null when the user has been deleted since the export' do
      author = User.create!(login: 'backup-author', firstname: 'Back', lastname: 'Up',
                            mail: 'backup-author@example.com')
      give_own_workflow(project, tracker, role).update!(created_by_id: author.id)

      document = described_class.document
      discard_project_workflows
      author.destroy

      restore.call(document)

      expect(ProjectWorkflowScope.find_by(project_id: project.id).created_by_id).to be_nil
    end
  end

  describe 'restoring onto a database that is not empty' do
    it 'leaves a workflow the project already has alone by default' do
      give_own_workflow(project, tracker, role)
      transition(project)
      document = described_class.document

      WorkflowRule.where(project_id: project.id).delete_all
      transition(project, from: s2, to: s1)

      report = restore.call(document)

      expect(report.scopes).to eq(0)
      expect(report.skipped_existing).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:old_status_id))
        .to eq([s2.id])
    end

    # OVERWRITE replaces the rules and keeps the decision -- INV-3's third
    # action -- so `created_by_id` is not moved by the restore either.
    it 'replaces the rules and keeps the decision when told to overwrite' do
      give_own_workflow(project, tracker, role)
      transition(project)
      document = described_class.document

      WorkflowRule.where(project_id: project.id).delete_all
      transition(project, from: s2, to: s1)

      report = restore.call(document, overwrite: true)

      expect(report.scopes).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:old_status_id, :new_status_id))
        .to eq([[s1.id, s2.id]])
      expect(own_workflow?(project, tracker, role)).to be(true)
    end
  end

  describe 'what a backup outlives' do
    it 'skips a combination whose project no longer exists, and names it' do
      give_own_workflow(other, tracker, role)
      transition(other)
      document = described_class.document
      discard_project_workflows
      gone = other.id
      other.destroy

      report = restore.call(document)

      expect(report.scopes).to eq(0)
      expect(report.skipped_missing.join).to match(/project #{gone}.*not found/)
    end

    # INV-2: the writers' whitelist is the validation, and a backup is data from
    # outside the application like any other. A status deleted since the export
    # is refused there and counted here.
    it 'refuses a rule naming a status that no longer exists' do
      give_own_workflow(project, tracker, role)
      transition(project)
      document = described_class.document
      discard_project_workflows
      document['rules'].first['new_status_id'] = IssueStatus.maximum(:id) + 1000

      report = restore.call(document)

      expect(report.rejected).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
      expect(own_workflow?(project, tracker, role)).to be(true)
    end

    # A rule with no decision behind it applies to nothing (INV-3), so writing
    # it back would put a row into the table that the resolver ignores.
    it 'does not restore a rule the backup records no decision for' do
      give_own_workflow(project, tracker, role)
      transition(project)
      document = described_class.document
      document['scopes'] = []
      discard_project_workflows

      report = restore.call(document)

      expect(report.orphan_rules).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'reports an unreadable rule type as an orphan rather than raising' do
      give_own_workflow(project, tracker, role)
      transition(project)
      document = described_class.document
      document['rules'].first['type'] = 'WorkflowSomethingElse'

      discard_project_workflows
      report = restore.call(document)

      expect(report.orphan_rules).to eq(1)
      expect(report.scopes).to eq(1)
    end
  end

  describe 'the duplicate rows a database from before 0.1.6 can carry' do
    it 'restores them as one row, which is what the deduplication task does' do
      give_own_workflow(project, tracker, role)
      transition(project)
      transition(project)
      document = described_class.document
      expect(document['rules'].size).to eq(2)

      discard_project_workflows
      restore.call(document)

      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
    end
  end

  describe 'INV-1: a restore is never a generic write' do
    it 'writes no row with a null project_id' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project)
      document = described_class.document
      discard_project_workflows

      generic = WorkflowTransition.where(project_id: nil).pluck(:id)
      restore.call(document)

      expect(WorkflowTransition.where(project_id: nil).pluck(:id)).to eq(generic)
    end
  end
end
