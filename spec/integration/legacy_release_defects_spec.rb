# frozen_string_literal: true

require_relative '../spec_helper'

# The five defects session B2 of the Jira migration read in 0.0.3 -- the release
# `main` carries and production runs -- each pinned against this version
# (2026-10-14). They are defects of the old code only; what is asserted here is
# that none of them came back.
#
# None of these examples can run against 0.0.3 itself: that release has no scope
# table, and the specs need one to arrange anything. How each was shown to fail
# there is recorded in docs/review/findings/2026-10-14-claude-migration-test.md,
# measured on a 5.1-stable-GEOxyz host with 0.0.3 installed.
describe 'Defects of the 0.0.3 release' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles,
           :enumerations, :projects_trackers, :enabled_modules

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:manager) { roles(:roles_001) }
  let(:developer) { roles(:roles_002) }
  let(:status_new) { issue_statuses(:issue_statuses_001) }
  let(:status_assigned) { issue_statuses(:issue_statuses_002) }
  let(:status_resolved) { issue_statuses(:issue_statuses_003) }

  before do
    WorkflowRule.where(tracker_id: tracker.id).delete_all
    ProjectWorkflowScope.delete_all
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
  end

  def transition(project_id, role, from, to, author: false, assignee: false)
    WorkflowTransition.create!(project_id: project_id, tracker_id: tracker.id, role_id: role.id,
                               old_status_id: from.id, new_status_id: to.id, author: author, assignee: assignee)
  end

  # B2 point 1. 0.0.3 decided "this project overrides" by the presence of rows,
  # so switching off the last transition of a project put its role back on the
  # generic workflow instead of leaving it with none.
  describe 'an own workflow emptied through the project matrix' do
    let(:user) { users(:users_002) } # jsmith, Manager on projects_001

    it 'stays an own, empty workflow rather than falling back to the generic one' do
      transition(nil, manager, status_new, status_assigned)
      give_own_workflow(project, tracker, manager)
      transition(project.id, manager, status_new, status_resolved)

      RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions(
        project, [tracker], [manager], { status_new.id.to_s => { status_resolved.id.to_s => { 'always' => '0' } } }
      )

      issue = Issue.create!(project: project, tracker: tracker, author: user, status: status_new,
                            subject: 'emptied', priority: IssuePriority.first)
      allowed = issue.new_statuses_allowed_to(user) - [status_new]

      expect(own_workflow?(project, tracker, manager)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(allowed).to be_empty
    end
  end

  # B2 point 3. 0.0.3 compared the cell value with `== '1' || == true`, so an
  # Integer 1 from a script read as "off" and deleted the transition it named.
  describe 'an Integer cell value' do
    it 'is rejected and counted, and the transition it names is left alone' do
      transition(nil, manager, status_new, status_assigned)

      result = RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
        nil, [tracker], [manager], { status_new.id.to_s => { status_assigned.id.to_s => { 'always' => 1 } } }
      )

      expect(result.rejected).to eq(1)
      expect(WorkflowTransition.where(project_id: nil, tracker_id: tracker.id).count).to eq(1)
    end
  end

  # B2 point 4. 0.0.3 limited Project#rolled_up_statuses to roles that have a
  # member somewhere in the tree, so a project without members had no status
  # filter and no status report at all.
  describe 'the status list of a project without members' do
    it 'is the generic one' do
      transition(nil, manager, status_new, status_assigned)
      bare = Project.create!(name: 'No members', identifier: 'pw-no-members', tracker_ids: [tracker.id])

      expect(bare.members).to be_empty
      expect(bare.rolled_up_statuses).to include(status_new, status_assigned)
    end
  end
end

# B2 point 2. Opening the generic matrix for two roles, one of which has an
# author-only transition and the other nothing, renders that cell as "no change"
# in the author table and as an unchecked box in the "always" table. Saving it
# unchanged submits `always => 0` for the cell. 0.0.3 deleted every row of the
# cell for both roles on that, so the first role silently lost its author rule.
#
# Driven through the real form: what is submitted is what the rendered page
# would send, not a payload written to match the fix.
describe WorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  render_views

  let(:tracker) { trackers(:trackers_001) }
  let(:manager) { roles(:roles_001) }
  let(:developer) { roles(:roles_002) }
  let(:status_new) { issue_statuses(:issue_statuses_001) }
  let(:status_assigned) { issue_statuses(:issue_statuses_002) }

  before do
    @request.session[:user_id] = 1
    WorkflowRule.where(tracker_id: tracker.id).delete_all
    ProjectWorkflowScope.delete_all
  end

  # The form's transitions[...] fields as a browser submits them: a checked box
  # wins over its hidden "0", an unchecked one leaves the hidden value, a
  # disabled one sends nothing, and a select sends its selected option.
  def submitted_transitions(html)
    page = Nokogiri::HTML(html)
    fields = {}
    page.css('input[name^="transitions["], select[name^="transitions["]').each do |field|
      next if field['disabled']

      name = field['name']
      value =
        if field.name == 'select'
          (field.at_css('option[selected]') || field.at_css('option'))['value']
        elsif field['type'] == 'checkbox'
          next unless field['checked']

          field['value']
        else
          field['value']
        end
      fields[name] = value
    end
    Rack::Utils.parse_nested_query(fields.map { |name, value| "#{CGI.escape(name)}=#{CGI.escape(value)}" }
                                         .join('&'))['transitions']
  end

  it 'keeps an author-only transition when two roles are saved unchanged' do
    WorkflowTransition.create!(project_id: nil, tracker_id: tracker.id, role_id: manager.id,
                               old_status_id: status_new.id, new_status_id: status_assigned.id,
                               author: true, assignee: false)
    selection = { role_id: [manager.id.to_s, developer.id.to_s], tracker_id: [tracker.id.to_s],
                  used_statuses_only: '0' }

    get :edit, params: selection
    transitions = submitted_transitions(response.body)
    expect(transitions.dig(status_new.id.to_s, status_assigned.id.to_s, 'author')).to eq('no_change')

    post :update, params: selection.merge(transitions: transitions)

    expect(WorkflowTransition.where(project_id: nil, tracker_id: tracker.id, role_id: manager.id,
                                    old_status_id: status_new.id, new_status_id: status_assigned.id,
                                    author: true)).to exist
    expect(WorkflowTransition.where(project_id: nil, tracker_id: tracker.id, role_id: developer.id)).to be_empty
  end

  # B2 point 5. 0.0.3 answered a target project that does not exist with
  # render_404 and went on to render again: ActionController::DoubleRenderError,
  # a 500. Core's copy screen no longer has a project dimension at all (ADR-003),
  # so the parameter is not read there; what matters is that it neither raises
  # nor writes a project row.
  it 'does not raise on a copy naming a target project that does not exist' do
    WorkflowTransition.create!(project_id: nil, tracker_id: tracker.id, role_id: manager.id,
                               old_status_id: status_new.id, new_status_id: status_assigned.id)

    expect do
      post :duplicate, params: { source_tracker_id: tracker.id, source_role_id: manager.id,
                                 target_tracker_ids: [tracker.id], target_role_ids: [developer.id],
                                 target_project_ids: ['999999'] }
    end.not_to raise_error

    expect(response).to have_http_status(:redirect)
    expect(WorkflowRule.where.not(project_id: nil)).to be_empty
  end
end

# B2 point 5, on the screen that does have a project dimension now.
describe ProjectWorkflowRulesController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:tracker) { trackers(:trackers_001) }
  let(:manager) { roles(:roles_001) }

  before do
    @request.session[:user_id] = 1
    WorkflowRule.where(tracker_id: tracker.id).delete_all
    ProjectWorkflowScope.delete_all
  end

  it 'refuses a copy into a project that does not exist and writes nothing' do
    WorkflowTransition.create!(project_id: nil, tracker_id: tracker.id, role_id: manager.id,
                               old_status_id: 1, new_status_id: 2)

    post :duplicate, params: { source_tracker_id: tracker.id, source_role_id: manager.id,
                               source_project_id: 'global', target_tracker_ids: [tracker.id],
                               target_role_ids: [manager.id], target_project_ids: ['999999'] }

    expect(response).to have_http_status(:ok)
    expect(flash[:error]).to eq(I18n.t(:error_workflow_copy_target_project))
    expect(WorkflowRule.where.not(project_id: nil)).to be_empty
    expect(ProjectWorkflowScope.count).to eq(0)
  end
end
