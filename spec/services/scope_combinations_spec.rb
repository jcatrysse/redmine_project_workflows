# frozen_string_literal: true

require_relative '../spec_helper'

# F03 and F04. A set of exact (project, tracker, role) triples is not a cross
# product, and every example here is about the difference: the copy screen acts
# on a set of pairs and skips any whose source resolves to the target itself, so
# a question asked of the cross product answers for combinations the copy never
# went near.
describe RedmineProjectWorkflows::Services::ScopeCombinations do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:other) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:second_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:second_tracker) { trackers(:trackers_002) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def transition(target, for_tracker = tracker, for_role = role)
    WorkflowTransition.create!(tracker_id: for_tracker.id, role_id: for_role.id,
                               old_status_id: status.id, new_status_id: new_status.id,
                               project_id: target&.id)
  end

  describe '.normalize' do
    it 'accepts records as well as ids' do
      expect(described_class.normalize([[project, tracker, role]]))
        .to eq([[project.id, tracker.id, role.id]])
    end

    it 'drops a triple that names no project, because the generic workflow has no scope' do
      expect(described_class.normalize([[nil, tracker.id, role.id]])).to eq([])
    end

    it 'drops a malformed triple rather than guessing at it' do
      expect(described_class.normalize([[project.id, tracker.id]])).to eq([])
    end

    it 'counts a repeated triple once' do
      pair = [project.id, tracker.id, role.id]

      expect(described_class.normalize([pair, pair.dup])).to eq([pair])
    end
  end

  describe '.for_project' do
    it 'turns the copied pairs into triples' do
      expect(described_class.for_project(project.id, [[tracker, role]]))
        .to eq([[project.id, tracker.id, role.id]])
    end

    # The generic workflow is the one thing that cannot be scoped.
    it 'contributes nothing for a copy whose target is the generic workflow' do
      expect(described_class.for_project(nil, [[tracker, role]])).to eq([])
    end
  end

  describe '.with_rules_and_no_scope' do
    it 'names a combination that has rules and no scope' do
      transition(project)

      expect(described_class.with_rules_and_no_scope([[project.id, tracker.id, role.id]], transitions))
        .to eq([[project.id, tracker.id, role.id]])
    end

    # An empty transitions scope would stop every issue in the project from
    # changing status, so a combination the copy left empty gets no scope.
    it 'says nothing about a combination with no rules' do
      expect(described_class.with_rules_and_no_scope([[project.id, tracker.id, role.id]], transitions))
        .to eq([])
    end

    it 'says nothing about a combination that already has a scope' do
      give_own_workflow(project, tracker, role)
      transition(project)

      expect(described_class.with_rules_and_no_scope([[project.id, tracker.id, role.id]], transitions))
        .to eq([])
    end

    # The cross-product trap. The set names two diagonal combinations; the third
    # one the cross product would contain has rules and no scope, and must not
    # come back from a question that was not asked about it.
    it 'stays inside the set it was given' do
      transition(project, second_tracker, second_role)

      answer = described_class.with_rules_and_no_scope(
        [[project.id, tracker.id, role.id], [project.id, second_tracker.id, role.id]], transitions
      )

      expect(answer).to eq([])
    end
  end

  describe '.own_empty_count' do
    it 'counts a scope with no rules under it' do
      give_own_workflow(project, tracker, role)

      expect(described_class.own_empty_count([[project.id, tracker.id, role.id]])).to eq(1)
    end

    it 'does not count a scope that has rules' do
      give_own_workflow(project, tracker, role)
      transition(project)

      expect(described_class.own_empty_count([[project.id, tracker.id, role.id]])).to eq(0)
    end

    it 'does not count a combination that inherits' do
      expect(described_class.own_empty_count([[project.id, tracker.id, role.id]])).to eq(0)
    end

    # Both rule types, because a copy moves both: the same pair can be own-empty
    # for transitions and perfectly populated for field permissions.
    it 'counts each rule type separately' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: status.id, field_name: 'due_date', rule: 'required')

      expect(described_class.own_empty_count([[project.id, tracker.id, role.id]])).to eq(1)
    end

    # The same trap from the other end: a neighbour's own empty workflow is not
    # this selection's business.
    it 'stays inside the set it was given' do
      give_own_workflow(other, tracker, role)

      expect(described_class.own_empty_count([[project.id, tracker.id, role.id]])).to eq(0)
    end

    it 'answers nothing for an empty selection without querying' do
      expect(described_class.own_empty_count([])).to eq(0)
      expect(described_class.own_empty_count(nil)).to eq(0)
    end
  end
end
