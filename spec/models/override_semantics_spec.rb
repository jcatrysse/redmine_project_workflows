# frozen_string_literal: true

#
# The inverted characterization suite for ADR-001.
#
# Until WP1 these examples lived in spec/characterization/override_semantics_spec.rb
# and asserted the opposite: that a single project rule silently took over the
# whole tracker and role, and that deleting the last rule silently gave it back.
# What decides now is the scope, and only the scope.
#
require_relative '../spec_helper'

describe 'Override semantics' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :enumerations

  let(:project) { projects(:projects_001) }
  let(:other) do
    Project.create!(name: 'Scope other', identifier: 'scope-other').tap do |p|
      p.trackers = [tracker]
      p.save!
      Member.create!(project: p, user: user, roles: [role])
    end
  end
  let(:role)    { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user)    { users(:users_002) }
  let(:s_new)   { issue_statuses(:issue_statuses_001) }
  let(:s_a)     { issue_statuses(:issue_statuses_002) }
  let(:s_b)     { issue_statuses(:issue_statuses_003) }
  let(:s_c)     { issue_statuses(:issue_statuses_004) }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    project.trackers = [tracker]
    project.save!
    global(s_new, s_a)
    global(s_new, s_b)
  end

  def global(from, to)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: from.id, new_status_id: to.id, project_id: nil)
  end

  def project_rule(from, to)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def issue
    @issue ||= Issue.create!(project: project, tracker: tracker, author: user,
                             subject: 'scope semantics', status_id: s_new.id)
  end

  def allowed
    Issue.find(issue.id).new_statuses_allowed_to(User.find(user.id)).map(&:id).sort
  end

  it 'inherits the generic workflow while the project has no scope' do
    expect(allowed).to eq([s_new.id, s_a.id, s_b.id].sort)
  end

  # Was: "DROPS every generic transition as soon as one project rule exists".
  it 'keeps the generic workflow when a project rule exists without a scope' do
    project_rule(s_new, s_c)

    expect(WorkflowTransition.where(project_id: nil).count).to eq(2)
    expect(allowed).to eq([s_new.id, s_a.id, s_b.id].sort)
    expect(allowed).not_to include(s_c.id)
  end

  it 'replaces the generic workflow once the project has a scope' do
    give_own_workflow(project, tracker, role)
    project_rule(s_new, s_c)

    # The generic rules are untouched in the database ...
    expect(WorkflowTransition.where(project_id: nil).count).to eq(2)
    # ... and a scope replaces rather than merges (INV-5).
    expect(allowed).to eq([s_new.id, s_c.id].sort)
  end

  it 'leaves other projects on the generic workflow' do
    give_own_workflow(project, tracker, role)
    project_rule(s_new, s_c)
    other_issue = Issue.create!(project: other, tracker: tracker, author: user,
                                subject: 'other', status_id: s_new.id)
    expect(other_issue.new_statuses_allowed_to(User.find(user.id)).map(&:id).sort)
      .to eq([s_new.id, s_a.id, s_b.id].sort)
  end

  # Was: "silently falls back to generic when the last project rule is removed".
  # This is the defect the whole scope model exists to fix (INV-3).
  it 'allows no transition at all when the scope is left without rules' do
    give_own_workflow(project, tracker, role)
    project_rule(s_new, s_c)
    WorkflowTransition.where(project_id: project.id).delete_all

    expect(ProjectWorkflowScope.count).to eq(1)
    expect(allowed).to eq([])
  end

  it 'tells an empty own workflow apart from inheritance' do
    give_own_workflow(project, tracker, role)
    expect(allowed).to eq([])

    ProjectWorkflowScope.delete_all
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
    expect(allowed).to eq([s_new.id, s_a.id, s_b.id].sort)
  end

  it 'scopes transitions and field permissions separately' do
    issue # the generic rule below makes due_date required, so create it first
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s_new.id, field_name: 'due_date', rule: 'required')
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)

    # Taking over the transitions must not take over the field permissions.
    rules = Issue.find(issue.id).workflow_rule_by_attribute(User.find(user.id))
    expect(rules['due_date']).to eq('required')
  end

  it 'replaces the generic field permissions under a permissions scope' do
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s_new.id, field_name: 'due_date', rule: 'required')
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s_new.id, field_name: 'start_date', rule: 'readonly')
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: s_new.id, field_name: 'due_date', rule: 'readonly')
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

    rules = Issue.find(issue.id).workflow_rule_by_attribute(User.find(user.id))
    expect(rules['due_date']).to eq('readonly')
    expect(rules).not_to have_key('start_date') # the generic rule does not apply
  end

  it 'keeps roles independent: only roles with a scope are overridden' do
    second_role = roles(:roles_002)
    Member.find_by(project_id: project.id, user_id: user.id)
          .update!(role_ids: [role.id, second_role.id])
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: second_role.id,
                               old_status_id: s_new.id, new_status_id: s_a.id, project_id: nil)
    give_own_workflow(project, tracker, role)
    project_rule(s_new, s_c)

    expect(allowed).to eq([s_new.id, s_a.id, s_c.id].sort)
  end

  # INV-6. A subproject is not a special case; it is simply another project.
  it 'does not inherit a scope from a parent project' do
    child = Project.create!(name: 'Scope child', identifier: 'scope-child', parent_id: project.id)
    child.trackers = [tracker]
    child.save!
    Member.create!(project: child, user: user, roles: [role])
    give_own_workflow(project, tracker, role)
    project_rule(s_new, s_c)

    child_issue = Issue.create!(project: child, tracker: tracker, author: user,
                                subject: 'child', status_id: s_new.id)
    expect(child_issue.new_statuses_allowed_to(User.find(user.id)).map(&:id).sort)
      .to eq([s_new.id, s_a.id, s_b.id].sort)
  end
end
