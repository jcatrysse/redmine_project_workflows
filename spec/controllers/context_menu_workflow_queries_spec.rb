# frozen_string_literal: true

require_relative '../spec_helper'

# The issue context menu asks every selected issue which statuses it may move to
# and offers their intersection. Measured on the combined GEOxyz 7.0 host
# (2026-10-14): about 28 workflow statements for 10 selected issues, one
# transitions query and one field-permission query per issue. Issues of one
# project, tracker and status ask the same question, so inside the multi-issue
# actions the answers are memoised (Services::WorkflowMemo,
# Patches::MultiIssueActionsPatch) and the count no longer grows with the
# selection.
#
# Asserted as a shape, like spec/services/hot_path_scale_spec.rb: the same
# request at two sizes costs the same number of statements against the plugin's
# two tables.
#
# Redmine 7 moved the issue menu to ContextMenus::IssuesController#index; 5.1
# and 6.1 serve it from ContextMenusController#issues. Same route either way.
MENU_CONTROLLER, MENU_ACTION =
  if defined?(ContextMenus::IssuesController)
    [ContextMenus::IssuesController, :index]
  else
    [ContextMenusController, :issues]
  end

describe MENU_CONTROLLER, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles,
           :enabled_modules, :projects_trackers, :enumerations

  render_views

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:user) { users(:users_002) } # jsmith, Manager on projects_001
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:s3) { issue_statuses(:issue_statuses_003) }

  before do
    WorkflowRule.where(tracker_id: tracker.id).delete_all
    ProjectWorkflowScope.delete_all
    WorkflowTransition.create!(project_id: nil, tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s1.id, new_status_id: s3.id)
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(project_id: project.id, tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s1.id, new_status_id: s2.id)
    @request.session[:user_id] = user.id
  end

  def issues(count)
    Array.new(count) do |index|
      Issue.create!(project: project, tracker: tracker, status: s1, subject: "menu #{index}",
                    author: user, priority: IssuePriority.first)
    end
  end

  def workflow_statements
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql].to_s
      seen << sql if sql.match?(/\b(project_workflow_scopes|workflows)\b/) && payload[:name] != 'SCHEMA'
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def menu_for(selection)
    RedmineProjectWorkflows::Current.reset
    workflow_statements { get MENU_ACTION, params: { ids: selection.map(&:id) } }
  end

  it 'costs the same number of workflow statements for 10 issues as for 20' do
    ten = menu_for(issues(10)).size
    twenty = menu_for(issues(20)).size

    expect(twenty).to eq(ten)
  end

  it 'offers the project\'s own transition and not the generic one' do
    menu_for(issues(3))

    expect(response).to have_http_status(:ok)
    statuses = assigns(:allowed_statuses).map(&:id)
    expect(statuses).to include(s2.id)
    expect(statuses).not_to include(s3.id)
  end

  it 'answers each issue as it did without the memo' do
    selection = issues(4)
    memoised = RedmineProjectWorkflows::Services::WorkflowMemo.during do
      selection.map { |issue| issue.new_statuses_allowed_to(user).map(&:id) }
    end

    fresh = selection.map { |issue| Issue.find(issue.id).new_statuses_allowed_to(user).map(&:id) }

    expect(memoised).to eq(fresh)
  end

  it 'does not answer from the memo after a rule write inside it' do
    issue = issues(1).first

    after = RedmineProjectWorkflows::Services::WorkflowMemo.during do
      expect(issue.new_statuses_allowed_to(user).map(&:id)).to include(s2.id)
      RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions(
        project, [tracker], [role], { s1.id.to_s => { s2.id.to_s => { 'always' => '0' } } }
      )
      Issue.find(issue.id).new_statuses_allowed_to(user).map(&:id)
    end

    expect(after).not_to include(s2.id)
  end

  # Outside the wrapped actions nothing is memoised, so a rule written with
  # plain ActiveRecord in the middle of a request is seen at once.
  it 'memoises nothing outside the multi-issue actions' do
    issue = issues(1).first
    expect(issue.new_statuses_allowed_to(user).map(&:id)).not_to include(s3.id)

    WorkflowTransition.create!(project_id: project.id, tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s1.id, new_status_id: s3.id)

    expect(Issue.find(issue.id).new_statuses_allowed_to(user).map(&:id)).to include(s3.id)
  end
end
