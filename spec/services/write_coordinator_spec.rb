# frozen_string_literal: true

require_relative '../spec_helper'

# WP13, audit finding F07. The generic population's coordination row: what it is
# keyed on, when it is created, and what it is not allowed to become.
#
# The *outcome* -- that two concurrent generic saves leave one row rather than
# two -- is asserted with a real second connection in
# spec/services/workflow_concurrency_spec.rb. These examples are about the shape
# of the thing that makes it possible, which is checkable on every adapter,
# SQLite included.
describe RedmineProjectWorkflows::Services::WriteCoordinator do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:permissions) { ProjectWorkflowScope::PERMISSIONS }

  before { ProjectWorkflowWriteLock.delete_all }

  describe '.lock_generic' do
    it 'creates one row per (rule type, tracker, role) named' do
      described_class.lock_generic(rule_type: transitions, pairs: [[tracker, role], [other_tracker, role]])

      expect(ProjectWorkflowWriteLock.pluck(:rule_type, :tracker_id, :role_id).sort)
        .to eq([[transitions, tracker.id, role.id], [transitions, other_tracker.id, role.id]].sort)
    end

    # The exact pairs, never their cross product. A lock on a row nobody is
    # writing is contention for nothing, and this is the same property
    # MatrixScope#pair_predicate holds for the rules themselves.
    it 'creates nothing for a pair the caller did not name' do
      described_class.lock_generic(rule_type: transitions, pairs: [[tracker, role], [other_tracker, other_role]])

      expect(ProjectWorkflowWriteLock.where(tracker_id: tracker.id, role_id: other_role.id)).to be_empty
    end

    # The row is the key. Two rows for one combination would be two locks for
    # one workflow, which is no lock at all.
    it 'creates the row once, however often the combination is written' do
      3.times { described_class.lock_generic(rule_type: transitions, pairs: [[tracker, role]]) }

      expect(ProjectWorkflowWriteLock.count).to eq(1)
    end

    # Keyed on the rule type as well: the transitions matrix and the field
    # permissions matrix write different rows of `workflows` and must not queue
    # behind each other.
    it 'keeps the two rule types apart' do
      described_class.lock_generic(rule_type: transitions, pairs: [[tracker, role]])
      described_class.lock_generic(rule_type: permissions, pairs: [[tracker, role]])

      expect(ProjectWorkflowWriteLock.pluck(:rule_type).sort).to eq([permissions, transitions].sort)
    end

    it 'answers the pairs it was given, so a caller can write pairs = lock_generic(...)' do
      pairs = [[tracker, role]]

      expect(described_class.lock_generic(rule_type: transitions, pairs: pairs)).to eq(pairs)
    end

    it 'touches nothing for an empty selection' do
      expect { described_class.lock_generic(rule_type: transitions, pairs: []) }
        .not_to(change { ProjectWorkflowWriteLock.count })
    end

    # Ids as well as records: the copy path holds pairs of records, and a caller
    # holding ids should not have to load two rows to take a lock.
    it 'accepts ids as well as records' do
      described_class.lock_generic(rule_type: transitions, pairs: [[tracker.id, role.id]])

      expect(ProjectWorkflowWriteLock.pluck(:tracker_id, :role_id)).to eq([[tracker.id, role.id]])
    end

    # INV-3. A scope row means "this project decides"; the generic workflow is
    # not a project, and giving it a scope row would be a fourth state in a
    # model whose whole purpose is that there are three.
    it 'creates no scope row for the generic workflow' do
      expect { described_class.lock_generic(rule_type: transitions, pairs: [[tracker, role]]) }
        .not_to(change { ProjectWorkflowScope.count })
    end
  end

  describe '.writable_pairs' do
    let(:project) { projects(:projects_001) }

    it 'answers every pair for a generic write, which has no scope to inherit' do
      pairs = described_class.writable_pairs(nil, [tracker], [role, other_role], transitions)

      expect(pairs).to eq([[tracker, role], [tracker, other_role]])
    end

    it 'answers only the pairs a project has taken over' do
      give_own_workflow(project, tracker, role)

      pairs = described_class.writable_pairs(project.id, [tracker], [role, other_role], transitions)

      expect(pairs).to eq([[tracker, role]])
    end

    # The project half takes no coordination row: its scope row already is one,
    # and it exists exactly when the combination is writable.
    it 'creates no coordination row for a project write' do
      give_own_workflow(project, tracker, role)

      expect { described_class.writable_pairs(project.id, [tracker], [role], transitions) }
        .not_to(change { ProjectWorkflowWriteLock.count })
    end
  end
end
