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
# Two kinds of example here. The first four are single-connection and assert
# the shape: the lock is taken, on the scope table, before anything is written
# -- by both writers, and not at all by a generic write. The last two run a
# real second connection and assert the outcome for both commit orders, because
# a lock that is taken and does not cover the right rows would satisfy the first
# four and none of the last two.
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

  # SQLite has no row locking to test and is not one of the nine supported
  # cells; PostgreSQL, MySQL and MariaDB all speak SELECT ... FOR UPDATE.
  def row_locking?
    ActiveRecord::Base.connection.adapter_name.match?(/postgres|mysql|trilogy/i)
  end

  def save_transitions
    writer.replace_transitions_for_project_id(project.id, [tracker], [role], matrix)
  end

  def return_to_generic
    scope_writer.return_to_inheritance(
      project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id], rule_type: transitions
    )
  end

  def project_rules
    WorkflowTransition.where(project_id: project.id)
  end

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    skip('the adapter has no row locking to assert') unless row_locking?
  end

  describe 'the lock a write takes' do
    def statements_during
      seen = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        seen << payload[:sql].to_s
      end
      yield
      seen
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def index_of_scope_lock(statements)
      statements.index { |sql| sql.match?(/project_workflow_scopes/i) && sql.match?(/FOR UPDATE/i) }
    end

    def index_of_first_rule_write(statements)
      statements.index { |sql| sql.match?(/\A\s*(INSERT INTO|DELETE FROM|UPDATE)\s+\W?workflows\b/i) }
    end

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

    # A generic write has no scope to lock and must not go looking for one:
    # project_id IS NULL is the whole of its predicate (INV-1, INV-4).
    it 'is not taken for a generic write' do
      statements = statements_during do
        writer.replace_transitions_for_project_id(nil, [tracker], [role], matrix)
      end

      expect(index_of_scope_lock(statements)).to be_nil
      expect(index_of_first_rule_write(statements)).not_to be_nil
    end
  end

  describe 'a save and a return to the generic workflow at the same moment' do
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

      skipped = save_transitions
      join!(returner)

      # The return to the generic workflow ran second and took everything with
      # it. What must not survive is a rule with no scope over it.
      expect(skipped).to eq(0)
      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(project_rules).to be_empty
    end

    it 'refuses the save when the scope went first' do
      give_own_workflow(project, tracker, role)
      main = Thread.current
      started = Queue.new
      finished = Queue.new
      skipped = Queue.new

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
      saver = in_parallel(started, finished) { skipped << save_transitions }

      return_to_generic
      join!(saver)

      expect(skipped.pop).to eq(1)
      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(project_rules).to be_empty
    end
  end
end
