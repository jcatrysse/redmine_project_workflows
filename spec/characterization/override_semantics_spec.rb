# frozen_string_literal: true
#
# CHARACTERIZATION TESTS - these lock in behaviour that is currently WRONG.
#
# The plugin derives "this project overrides the generic workflow" from the mere
# existence of project rows. There is no way to express:
#   * an override that adds to the generic rules, or
#   * an override that is deliberately empty.
#
# Every example below passes today and documents that limitation. When explicit
# override scopes are introduced, these examples must be inverted, not repaired.
#
require_relative '../spec_helper'

describe 'Override semantics' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :enumerations

  let(:project) { projects(:projects_001) }
  let(:other) do
    Project.create!(name: 'Characterization other', identifier: 'char-other').tap do |p|
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
                             subject: 'characterization', status_id: s_new.id)
  end

  def allowed
    Issue.find(issue.id).new_statuses_allowed_to(User.find(user.id)).map(&:id).sort
  end

  it 'inherits the generic workflow while the project has no rules of its own' do
    expect(allowed).to eq([s_new.id, s_a.id, s_b.id].sort)
  end

  it 'DROPS every generic transition as soon as one project rule exists' do
    project_rule(s_new, s_c)

    # The generic rules are untouched in the database ...
    expect(WorkflowTransition.where(project_id: nil).count).to eq(2)
    # ... but they no longer apply to this project.
    expect(allowed).to eq([s_new.id, s_c.id].sort)
  end

  it 'leaves other projects on the generic workflow' do
    project_rule(s_new, s_c)
    other_issue = Issue.create!(project: other, tracker: tracker, author: user,
                                subject: 'other', status_id: s_new.id)
    expect(other_issue.new_statuses_allowed_to(User.find(user.id)).map(&:id).sort)
      .to eq([s_new.id, s_a.id, s_b.id].sort)
  end

  it 'silently falls back to generic when the last project rule is removed' do
    project_rule(s_new, s_c)
    WorkflowTransition.where(project_id: project.id).delete_all
    expect(allowed).to eq([s_new.id, s_a.id, s_b.id].sort)
  end

  it 'applies the same all-or-nothing rule to field permissions' do
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s_new.id, field_name: 'due_date', rule: 'required')
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s_new.id, field_name: 'start_date', rule: 'readonly')
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: s_new.id, field_name: 'due_date', rule: 'readonly')

    rules = Issue.find(issue.id).workflow_rule_by_attribute(User.find(user.id))
    expect(rules['due_date']).to eq('readonly')
    expect(rules).not_to have_key('start_date')   # the generic rule is gone
  end

  it 'keeps roles independent: only roles with project rules are overridden' do
    second_role = roles(:roles_002)
    Member.find_by(project_id: project.id, user_id: user.id)
          .update!(role_ids: [role.id, second_role.id])
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: second_role.id,
                               old_status_id: s_new.id, new_status_id: s_a.id, project_id: nil)
    project_rule(s_new, s_c)

    expect(allowed).to eq([s_new.id, s_a.id, s_c.id].sort)
  end
end
