# frozen_string_literal: true

require_relative '../spec_helper'

describe Project, type: :model do
  fixtures :projects, :roles, :trackers, :issue_statuses, :enabled_modules, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before do
    project.enabled_modules << EnabledModule.new(name: 'issue_tracking') if project.enabled_modules.empty?
    other_project.enabled_modules << EnabledModule.new(name: 'issue_tracking') if other_project.enabled_modules.empty?
    project.trackers << tracker unless project.trackers.include?(tracker)
    other_project.trackers << tracker unless other_project.trackers.include?(tracker)
    ProjectWorkflowScope.delete_all
  end

  it 'returns only statuses from global workflows when no project overrides exist' do
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

    status_ids = project.rolled_up_statuses.pluck(:id)

    expect(status_ids).to include(global_status.id)
    expect(status_ids).not_to include(project_status.id)
  end

  it 'returns project-specific statuses for scoped roles' do
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

    status_ids = project.rolled_up_statuses.pluck(:id)

    expect(status_ids).to include(project_status.id)
    expect(status_ids).not_to include(global_status.id)
  end

  it 'returns empty statuses when the project has no trackers' do
    target_project = other_project
    target_project.trackers.clear
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

    status_ids = target_project.rolled_up_statuses.pluck(:id)

    expect(status_ids).to be_empty
  end

  # A project of its own rather than a fixture: the memberships of the
  # fixtures' projects are easy to read the wrong way round, and these examples
  # are precisely about a project that has none.
  def project_with_tracker(identifier, parent: nil, trackers: [tracker])
    created = Project.new(name: identifier, identifier: identifier)
    created.parent = parent if parent
    created.save!
    # A new project already gets Setting.default_projects_modules, which
    # normally includes issue_tracking; adding a second row for it is what
    # makes the association invalid.
    created.enabled_modules << EnabledModule.new(name: 'issue_tracking') unless created.module_enabled?(:issue_tracking)
    created.trackers = trackers
    created.save!
    created
  end

  def generic_transition(from, to, for_role: role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: for_role.id,
      old_status_id: from.id,
      new_status_id: to.id,
      project_id: nil,
      author: false,
      assignee: false
    )
  end

  def project_transition(target_project, from, to, for_role: role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: for_role.id,
      old_status_id: from.id,
      new_status_id: to.id,
      project_id: target_project.id,
      author: false,
      assignee: false
    )
  end

  describe 'without a role filter (external F08)' do
    before { WorkflowTransition.delete_all }

    it 'returns the generic used statuses for a project without members' do
      generic_transition(old_status, global_status)
      member_less = project_with_tracker('no-members')

      expect(member_less.members).to be_empty
      expect(member_less.rolled_up_statuses.pluck(:id)).to contain_exactly(old_status.id, global_status.id)
    end

    it 'counts a role that has no members anywhere' do
      unmanned = Role.create!(name: 'Nobody has this', permissions: [:add_issues])
      generic_transition(old_status, project_status, for_role: unmanned)
      member_less = project_with_tracker('no-members-either')

      expect(member_less.rolled_up_statuses.pluck(:id)).to include(project_status.id)
    end
  end

  describe 'across a project tree (external F08)' do
    before { WorkflowTransition.delete_all }

    it "includes a subproject's own statuses in the parent's rolled-up list" do
      generic_transition(old_status, global_status)
      parent = project_with_tracker('tree-parent')
      child = project_with_tracker('tree-child', parent: parent)
      give_own_workflow(child, tracker, role)
      project_transition(child, old_status, project_status)

      status_ids = parent.reload.rolled_up_statuses.pluck(:id)

      expect(status_ids).to include(project_status.id)
      expect(status_ids).to include(global_status.id)
    end

    it 'answers a subproject with its own workflow alone, not the generic one' do
      generic_transition(old_status, global_status)
      parent = project_with_tracker('lone-parent')
      child = project_with_tracker('lone-child', parent: parent)
      give_own_workflow(child, tracker, role)
      project_transition(child, old_status, project_status)

      # The child has no descendants, so this is its own scope and nothing else:
      # a scope replaces the generic workflow, it does not add to it (INV-5).
      expect(child.reload.rolled_up_statuses.pluck(:id)).to contain_exactly(old_status.id, project_status.id)
    end

    it 'keeps the generic statuses when only one project in the tree overrides' do
      generic_transition(old_status, global_status)
      parent = project_with_tracker('mixed-parent')
      project_with_tracker('mixed-child', parent: parent)
      give_own_workflow(parent, tracker, role)
      project_transition(parent, old_status, project_status)

      status_ids = parent.reload.rolled_up_statuses.pluck(:id)

      expect(status_ids).to include(project_status.id)
      expect(status_ids).to include(global_status.id)
    end

    it 'ignores an archived subproject, as core does' do
      generic_transition(old_status, global_status)
      parent = project_with_tracker('archived-parent', trackers: [])
      child = project_with_tracker('archived-child', parent: parent)
      give_own_workflow(child, tracker, role)
      project_transition(child, old_status, project_status)
      expect(child.archive).to be_truthy

      expect(parent.reload.rolled_up_statuses.pluck(:id)).to be_empty
    end
  end
end
