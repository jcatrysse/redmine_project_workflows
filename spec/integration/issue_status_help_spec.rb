# frozen_string_literal: true

require_relative '../spec_helper'

# WP8, the half that needed no new code -- only proof.
#
# Redmine core already ships a status help icon on the issue form: an
# `icon-help` link next to the status select, opening `#issue_statuses_description`,
# a <dl> of status name and IssueStatus#description. It renders only when at
# least one of the available statuses has a description, which is why an
# installation that has never filled them in concludes the feature is absent.
#
# The list it renders is `@allowed_statuses`, which is
# Issue#new_statuses_allowed_to -- a method this plugin replaces in full. So
# core's own modal already describes the project's *own* effective workflow
# rather than the generic one, and what needs asserting is exactly that: it must
# never name a status only another project's rules reach (INV-4), and it must
# disappear rather than fall back to the generic list when a project's own
# workflow is empty (INV-3).
#
# These are the assertions that would catch the plugin quietly reverting to
# core's project-blind query. Nothing here is the plugin's markup, and there is
# no Deface override involved.
describe IssuesController, type: :controller do
  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :enumerations,
           :issues, :issue_categories, :versions

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }
  let(:foreign_status) { issue_statuses(:issue_statuses_003) }

  before do
    @request.session[:user_id] = 2
    # Set here rather than relied on from the fixtures: core renders the icon and
    # the modal only when at least one available status has a description, which
    # is the paragraph WP8 adds to the README, and a spec that reads a fixture's
    # description would pass whether or not this spec arranged anything.
    describe_statuses(IssueStatus.all, text: 'Description of %<name>s')
  end

  # No update_all: a bulk write skips the model, and these are a handful of rows.
  def describe_statuses(statuses, text: nil)
    statuses.each { |status| status.update!(description: text && format(text, name: status.name)) }
  end

  def transition(from, to, project_id: nil)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project_id,
                               old_status_id: from.respond_to?(:id) ? from.id : from,
                               new_status_id: to.id)
  end

  def an_issue(status: new_status)
    Issue.create!(project: project, tracker: tracker, status: status,
                  author_id: 2, subject: 'status help spec')
  end

  # The modal is core's, so this locates it rather than the plugin's markup.
  def modal
    response.body[%r{<div class="modal" id="issue_statuses_description">.*?</div>}m]
  end

  it 'names the statuses the generic workflow reaches while the project inherits' do
    transition(new_status, assigned)

    get :edit, params: { id: an_issue.id }

    expect(response).to have_http_status(:ok)
    expect(modal).to be_present
    expect(modal).to include(assigned.name)
  end

  # INV-4, on core's own screen. A rule stored against another project must be
  # invisible here, and before the plugin's query replaced core's it was not.
  it 'never names a status only another project rules reach' do
    transition(new_status, assigned)
    give_own_workflow(other_project, tracker, role)
    transition(new_status, foreign_status, project_id: other_project.id)

    get :edit, params: { id: an_issue.id }

    expect(modal).to be_present
    expect(modal).to include(assigned.name)
    expect(modal).not_to include(foreign_status.name)
  end

  it 'names the project own statuses once the project has taken over' do
    transition(new_status, assigned)
    give_own_workflow(project, tracker, role)
    transition(new_status, foreign_status, project_id: project.id)

    get :edit, params: { id: an_issue.id }

    expect(modal).to be_present
    expect(modal).to include(foreign_status.name)
    expect(modal).not_to include(assigned.name)
  end

  # INV-3. An own *empty* workflow permits nothing at all, and what core then
  # renders is stronger than an empty dropdown: `new_statuses_allowed_to` returns
  # [] -- it appends the initial status only when the workflow permitted
  # something -- so `@allowed_statuses.present?` is false and core replaces the
  # select with a plain label. No select, no help icon, no modal, and nothing
  # anywhere on the form saying why.
  #
  # That is the case the panel exists for, and this is the assertion that the
  # generic list does not quietly reappear instead.
  it 'offers no status control at all for an own empty workflow' do
    transition(new_status, assigned)
    give_own_workflow(project, tracker, role)

    get :edit, params: { id: an_issue.id }

    expect(response).to have_http_status(:ok)
    expect(modal).to be_nil
    expect(response.body).not_to include('id="issue_status_id"')
    expect(response.body).not_to include(assigned.name)
  end

  # And the case that made the feature look absent: no description anywhere means
  # no icon and no modal, which is core's behaviour and not something to fix.
  it 'renders no modal at all when no status has a description' do
    describe_statuses(IssueStatus.all)
    transition(new_status, assigned)

    get :edit, params: { id: an_issue.id }

    expect(response).to have_http_status(:ok)
    expect(modal).to be_nil
    expect(response.body).not_to include('showModal(\'issue_statuses_description\'')
  end
end
