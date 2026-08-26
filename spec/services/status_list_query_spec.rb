# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::StatusListQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before { ProjectWorkflowScope.delete_all }

  it 'returns global statuses when the project has no scope' do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: [role.id]
    )

    expect(status_ids).to include(global_status.id)
    expect(status_ids).not_to include(project_status.id)
  end

  it 'prefers project statuses over global ones for scoped roles' do
    WorkflowTransition.delete_all
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: [role.id]
    )

    expect(status_ids).to include(project_status.id)
    expect(status_ids).not_to include(global_status.id)
  end

  it 'returns empty when trackers are missing' do
    status_ids = described_class.status_ids_for_pairs(
      pairs: [],
      role_ids: [role.id]
    )

    expect(status_ids).to be_empty
  end

  it 'returns empty when role ids are missing' do
    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: []
    )

    expect(status_ids).to be_empty
  end

  it 'returns empty when role ids are missing even with transitions present' do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: []
    )

    expect(status_ids).to be_empty
  end

  it 'applies no role filter at all when role ids are nil' do
    WorkflowTransition.delete_all
    # A role nobody can use for a workflow. Core's own queries here carry no
    # role predicate, so its rows count; the previous implementation filtered
    # on Role#consider_workflow? and dropped them.
    unmanned = Role.create!(name: 'No issue permissions', permissions: [])
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: unmanned.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    expect(unmanned).not_to be_consider_workflow

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: nil
    )

    expect(status_ids).to include(global_status.id)
  end

  describe '.status_ids_for_pairs' do
    let(:second_tracker) { trackers(:trackers_002) }

    before { WorkflowTransition.delete_all }

    it 'reads each project in the list against its own scope' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: project_status.id,
        project_id: project.id, author: false, assignee: false
      )
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: global_status.id,
        project_id: nil, author: false, assignee: false
      )

      # The first project answers for itself, the second inherits. Both
      # populations are reachable; neither hides the other (INV-6).
      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id]]
      )

      expect(status_ids).to include(project_status.id)
      expect(status_ids).to include(global_status.id)
    end

    it 'drops the generic rows only for the tracker and role that every pair overrides' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, role)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: global_status.id,
        project_id: nil, author: false, assignee: false
      )
      WorkflowTransition.create!(
        tracker_id: second_tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: project_status.id,
        project_id: nil, author: false, assignee: false
      )

      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id],
                [project.id, second_tracker.id]]
      )

      expect(status_ids).not_to include(global_status.id)
      expect(status_ids).to include(project_status.id)
    end

    it 'reads the generic workflow for a pair whose project id is nil' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: global_status.id,
        project_id: nil, author: false, assignee: false
      )

      status_ids = described_class.status_ids_for_pairs(pairs: [[nil, tracker.id]])

      expect(status_ids).to contain_exactly(old_status.id, global_status.id)
    end

    it 'returns empty for an empty list of pairs' do
      expect(described_class.status_ids_for_pairs(pairs: [])).to be_empty
    end
  end
end
