# frozen_string_literal: true

require_relative '../spec_helper'

describe Issue, type: :model do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user) { users(:users_002) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before do
    member = Member.where(project: project, user: user).first_or_initialize
    member.roles = [role] if member.new_record? || member.roles.empty?
    member.save!

    WorkflowTransition.where(tracker_id: tracker.id, role_id: role.id).delete_all
    ProjectWorkflowScope.delete_all
  end

  it 'uses only global transitions for new issues in projects without overrides' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, author: user)

    statuses = issue.new_statuses_allowed_to(user, true)

    expect(statuses).to include(global_status)
    expect(statuses).not_to include(project_status)
  end

  it 'prefers project-specific transitions over global ones for new issues' do
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, author: user)

    statuses = issue.new_statuses_allowed_to(user, true)

    expect(statuses).to include(project_status)
    expect(statuses).not_to include(global_status)
  end

  describe '#workflow_rule_by_attribute' do
    let(:status) { issue_statuses(:issue_statuses_001) }

    it 'returns project-specific permission rules when the project has a scope' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        rule: 'required',
        project_id: nil
      )
      WorkflowPermission.create!(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        rule: 'readonly',
        project_id: project.id
      )

      issue = Issue.new(project: project, tracker: tracker, status: status, author: user)

      rules = issue.workflow_rule_by_attribute(user)

      expect(rules['subject']).to eq('readonly')
    end

    it 'falls back to global rules when no project overrides exist' do
      WorkflowPermission.create!(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        rule: 'required',
        project_id: nil
      )

      issue = Issue.new(project: project, tracker: tracker, status: status, author: user)

      rules = issue.workflow_rule_by_attribute(user)

      expect(rules['subject']).to eq('required')
    end
  end

  it 'falls back to the default status when no transitions are defined' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, author: user)

    statuses = issue.new_statuses_allowed_to(user, true)

    expect(statuses).to contain_exactly(issue.default_status)
  end

  describe '#tracker= (claude F02)' do
    let(:other_role) { roles(:roles_002) }
    let(:bug) { trackers(:trackers_001) }
    let(:feature) { trackers(:trackers_002) }
    let(:new_status) { issue_statuses(:issue_statuses_001) }

    before { WorkflowTransition.delete_all }

    def issue_with_status(status)
      issue = Issue.new(project: project, tracker: bug, author: user, subject: 'Tracker change')
      issue.status = status
      issue
    end

    def transition(from, to, for_project: nil, for_role: role, for_tracker: feature)
      WorkflowTransition.create!(
        tracker_id: for_tracker.id,
        role_id: for_role.id,
        old_status_id: from.id,
        new_status_id: to.id,
        project_id: for_project&.id,
        author: false,
        assignee: false
      )
    end

    it "does not keep a status that only another project's workflow uses" do
      give_own_workflow(other_project, feature, role)
      transition(project_status, global_status, for_project: other_project)
      issue = issue_with_status(project_status)

      issue.tracker = feature

      # This project inherits, and the generic workflow for the new tracker does
      # not use Resolved at all. Core's global union does, because it counts the
      # other project's rows.
      expect(issue.status).to eq(feature.default_status)
    end

    it 'keeps a status that this project\'s own workflow uses' do
      give_own_workflow(project, feature, role)
      transition(project_status, global_status, for_project: project)
      issue = issue_with_status(project_status)

      issue.tracker = feature

      expect(issue.status).to eq(project_status)
    end

    it 'keeps nothing for a project whose own workflow is empty' do
      transition(project_status, global_status)
      give_own_workflow(project, feature, role)
      issue = issue_with_status(project_status)

      issue.tracker = feature

      # A scope with no rules is an own *empty* workflow, not inheritance
      # (INV-3): the generic rule that uses Resolved does not apply here.
      expect(issue.status).to eq(feature.default_status)
    end

    it 'keeps a status the generic workflow uses for a project that inherits' do
      transition(project_status, global_status)
      issue = issue_with_status(project_status)

      issue.tracker = feature

      expect(issue.status).to eq(project_status)
    end

    it 'applies no role filter, so another role\'s generic rule still counts' do
      transition(project_status, global_status, for_role: other_role)
      issue = issue_with_status(project_status)

      issue.tracker = feature

      expect(user.roles_for_project(project)).to eq([role])
      expect(issue.status).to eq(project_status)
    end

    it 'leaves Tracker#issue_status_ids a global union' do
      give_own_workflow(other_project, feature, role)
      transition(project_status, global_status, for_project: other_project)

      # Deliberate: narrowing the tracker's own list to the generic rules would
      # take a status away from an issue in a project that does use it. The two
      # call sites in Issue are project-aware instead (claude F02).
      expect(Tracker.find(feature.id).issue_status_ids).to include(project_status.id)
    end
  end

  describe '#new_statuses_allowed_to after a tracker change (claude F02)' do
    let(:other_role) { roles(:roles_002) }
    let(:bug) { trackers(:trackers_001) }
    let(:feature) { trackers(:trackers_002) }
    let(:new_status) { issue_statuses(:issue_statuses_001) }

    before { WorkflowTransition.delete_all }

    it "treats the issue's own status as the starting point even when only another role's rules use it" do
      # Nothing the user's role can do from Resolved; another role's generic
      # rule is what puts Resolved in the new tracker's workflow at all.
      WorkflowTransition.create!(tracker_id: feature.id, role_id: other_role.id,
                                 old_status_id: project_status.id, new_status_id: global_status.id,
                                 project_id: nil, author: false, assignee: false)
      WorkflowTransition.create!(tracker_id: feature.id, role_id: role.id,
                                 old_status_id: new_status.id, new_status_id: global_status.id,
                                 project_id: nil, author: false, assignee: false)

      # projects_trackers is not in this spec's fixture list, so the project has
      # to be told which trackers it runs before an issue can be validated.
      project.trackers = [bug, feature]
      issue = Issue.create!(project: project, tracker: bug, author: user,
                            subject: 'Role filter', status: project_status)
      issue.tracker = feature

      # A role filter here would answer "Resolved is not in this workflow", fall
      # back to the tracker's default status, and offer the transitions out of
      # *that* -- silently turning a Resolved issue into a New one.
      expect(issue.new_statuses_allowed_to(user)).to be_empty
    end
  end
end
