# frozen_string_literal: true

require_relative '../spec_helper'

# F02. A matrix save asks whether the project runs its own workflow for a
# (tracker, role) and then writes the rules. Those used to be two decisions
# taken from one unlocked read, and between them a second request could return
# the project to the generic workflow: the scope and its rules went, the save
# then wrote its rules anyway, and the table was left holding project rules
# under no scope. The resolver ignores them (INV-3: a project without a scope
# follows the generic workflow), so the save reported success over a change
# that had no effect and left rows behind that nothing would ever read.
#
# F07, and the second half of this file. A **generic** write has no scope row --
# the generic workflow is what a project inherits, not something a project
# decides -- so until WP13 it locked nothing at all, and two administrators
# saving the same matrix at the same moment could both find no row to delete and
# both insert one. Core has the identical race; the plugin is now the write path
# for both populations and holds one policy for them, with the generic
# population's coordination row on a table of the plugin's own
# (Services::WriteCoordinator).
#
# Two kinds of example here. The single-connection ones assert the shape: which
# table the lock is taken on, and that it is taken before anything is written.
# The ones that run a real second connection assert the outcome, because a lock
# that is taken and does not cover the right rows would satisfy every example of
# the first kind and none of the second.
describe 'Concurrent scope decisions' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:from_status) { issue_statuses(:issue_statuses_001) }
  let(:to_status) { issue_statuses(:issue_statuses_002) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:writer) { RedmineProjectWorkflows::Services::TransitionWriter }
  let(:scope_writer) { RedmineProjectWorkflows::Services::ScopeWriter }
  let(:matrix) { {from_status.id.to_s => {to_status.id.to_s => {'always' => '1'}}} }

  def save_transitions
    writer.replace_transitions_for_project_id(project.id, [tracker], [role], matrix)
  end

  def return_to_generic
    scope_writer.return_to_inheritance(
      project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id], rule_type: transitions
    )
  end

  def save_generic
    writer.replace_transitions_for_project_id(nil, [tracker], [role], matrix)
  end

  def project_rules
    WorkflowTransition.where(project_id: project.id)
  end

  def generic_rules
    WorkflowTransition.where(project_id: nil)
  end

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    skip('the adapter has no row locking to assert') unless row_locking?
  end

  # statements_during, index_of_scope_lock, index_of_first_rule_write and
  # row_locking? live in spec_helper.rb: the copy screen has to answer the same
  # question from a controller spec (finding F01), and two copies of the helpers
  # would be the same shape of mistake the finding was about.
  describe 'the lock a write takes' do
    it 'is taken on the scope rows before a project save writes a rule' do
      give_own_workflow(project, tracker, role)

      statements = statements_during { save_transitions }

      expect(index_of_scope_lock(statements)).not_to be_nil
      expect(index_of_first_rule_write(statements)).not_to be_nil
      expect(index_of_scope_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    it 'is taken on the scope rows before a return to the generic workflow deletes one' do
      give_own_workflow(project, tracker, role)

      statements = statements_during { return_to_generic }

      expect(index_of_scope_lock(statements)).not_to be_nil
      expect(index_of_scope_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    # The lock lives in MatrixScope, which both writers extend, so the field
    # permissions matrix has to take it too -- it writes into the same scope
    # table under a different rule type, and the race is the same one.
    it 'is taken on the scope rows before a project saves its field permissions' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      statements = statements_during do
        RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
          project.id, [tracker], [role], {from_status.id.to_s => {'subject' => 'required'}}
        )
      end

      expect(index_of_scope_lock(statements)).not_to be_nil
      expect(index_of_first_rule_write(statements)).not_to be_nil
      expect(index_of_scope_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    # **Inverted in WP13, and it used to assert the opposite.** The example that
    # stood here read "is not taken for a generic write", and it pinned audit
    # finding F07: a generic write has no scope row, so it took nothing, and two
    # administrators saving the same matrix at the same moment could both find
    # no row to delete and both insert one. The generic population now has a
    # coordination row of the plugin's own.
    #
    # Both halves matter. The lock is taken -- and it is taken on the plugin's
    # own table, never on the scope table: a scope row means "this project
    # decides" (INV-3), and the generic workflow is not a project (INV-1, INV-4).
    it 'is taken on the plugin\'s own row, and not on a scope row, for a generic write' do
      statements = statements_during do
        writer.replace_transitions_for_project_id(nil, [tracker], [role], matrix)
      end

      expect(index_of_write_lock(statements)).not_to be_nil
      expect(index_of_scope_lock(statements)).to be_nil
      expect(index_of_first_rule_write(statements)).not_to be_nil
      expect(index_of_write_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    # The field permissions matrix writes into the same population under the
    # other rule type, and the coordination row is keyed on the rule type, so it
    # has to take its own.
    it 'is taken for a generic field permissions write too' do
      statements = statements_during do
        RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
          nil, [tracker], [role], {from_status.id.to_s => {'subject' => 'required'}}
        )
      end

      expect(index_of_write_lock(statements)).not_to be_nil
      expect(index_of_write_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    # The row is created once and then found. A second write of the same
    # combination must not insert a second one -- two rows for one key would be
    # two locks for one workflow, which is no lock at all.
    it 'creates one coordination row per (rule type, tracker, role), however often it is written' do
      3.times { writer.replace_transitions_for_project_id(nil, [tracker], [role], matrix) }

      expect(ProjectWorkflowWriteLock.where(tracker_id: tracker.id, role_id: role.id).count).to eq(1)
    end

    # A selection the writer refuses before it reaches the table takes nothing:
    # a payload the whitelist empties returns from the writer having written
    # nothing, and locking a row for a write that will not happen is contention
    # for nothing.
    it 'is not taken when the payload has nothing the whitelist accepts' do
      statements = statements_during do
        writer.replace_transitions_for_project_id(nil, [tracker], [role], {'0' => {'0' => {'nope' => '1'}}})
      end

      expect(index_of_write_lock(statements)).to be_nil
      expect(index_of_first_rule_write(statements)).to be_nil
    end
  end

  describe 'two write paths at the same moment' do
    # Two connections that can see each other's committed work, which the
    # suite's usual one-transaction-per-example cannot give: everything this
    # example arranges would be invisible to the second connection.
    if respond_to?(:use_transactional_tests=)
      self.use_transactional_tests = false
    else
      self.use_transactional_fixtures = false
    end

    after do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
      ProjectWorkflowWriteLock.delete_all
    end

    # How long the hooked transaction waits for the other one before carrying
    # on. Under the lock the other one is stopped dead on the scope row and the
    # whole window elapses; without it, it finishes in milliseconds and the
    # wait ends early -- which is precisely the interleaving that used to leave
    # rules under no scope. So this is what the two examples below cost when
    # they pass, and it is the price of testing the thing at all.
    def wait_for_the_other(queue)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.5
      sleep(0.02) while queue.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end

    # The second connection. Nothing of RSpec's is touched inside it: the
    # values it needs are read before it starts.
    def in_parallel(started, finished)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          started.pop
          yield
        ensure
          finished << true
        end
      end
    end

    def join!(thread)
      raise 'the second connection never came back -- it is still waiting for a lock' unless thread.join(30)
    end

    it 'leaves no rules behind when the scope goes while the save is in flight' do
      give_own_workflow(project, tracker, role)
      main = Thread.current
      started = Queue.new
      finished = Queue.new

      # The save has taken its lock and is about to write. The other request
      # arrives here, and must not be able to get past it.
      allow(writer).to receive(:write_pairs).and_wrap_original do |original, *args|
        if Thread.current == main
          started << true
          wait_for_the_other(finished)
        end
        original.call(*args)
      end
      returner = in_parallel(started, finished) { return_to_generic }

      result = save_transitions
      join!(returner)

      # The return to the generic workflow ran second and took everything with
      # it. What must not survive is a rule with no scope over it.
      expect(result.skipped).to eq(0)
      expect(result.written).to eq(1)
      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(project_rules).to be_empty
    end

    it 'refuses the save when the scope went first' do
      give_own_workflow(project, tracker, role)
      main = Thread.current
      started = Queue.new
      finished = Queue.new
      results = Queue.new

      # This time the return to the generic workflow holds the lock, and it is
      # the save that has to wait -- and then find the combination inheriting
      # and refuse it, rather than writing rules into a scope that is gone.
      allow(scope_writer).to receive(:delete_rules).and_wrap_original do |original, *args|
        if Thread.current == main
          started << true
          wait_for_the_other(finished)
        end
        original.call(*args)
      end
      saver = in_parallel(started, finished) { results << save_transitions }

      return_to_generic
      join!(saver)

      expect(results.pop).to have_attributes(written: 0, skipped: 1)
      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(project_rules).to be_empty
    end

    # F07 itself, on the population that had no lock at all until WP13.
    #
    # Both connections save the same generic cell, which no row yet carries.
    # The pause is between the delete and the insert, and it has to be: pausing
    # before the delete would prove nothing, because READ COMMITTED lets the
    # second delete see the first connection's committed row and remove it.
    # Held open across the insert, the interleaving is the real one -- each
    # connection's DELETE finds nothing to take and both INSERT, which is the
    # duplicate the README documents and the repair rake task exists for.
    #
    # Verified red on the old code by returning early from
    # WriteCoordinator.lock_generic: two rows, no error, both saves reporting
    # success.
    it 'leaves one generic rule, not two, when two administrators save the same cell' do
      main = Thread.current
      started = Queue.new
      finished = Queue.new

      allow(writer).to receive(:insert_transition_rows).and_wrap_original do |original, *args|
        if Thread.current == main
          started << true
          wait_for_the_other(finished)
        end
        original.call(*args)
      end
      other = in_parallel(started, finished) { save_generic }

      save_generic
      join!(other)

      expect(generic_rules.count).to eq(1)
    end
  end
end
