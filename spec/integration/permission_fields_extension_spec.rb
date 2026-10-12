# frozen_string_literal: true

require_relative '../spec_helper'

# Round 6 (Jan, 2026-10-12): a neighbour plugin's field-permission fields --
# Impact and Urgency of redmine_itil_priority first -- appear on this plugin's
# project matrix, its administration matrix and in what the comparison screen
# counts as offered, all three fed from one list
# (RedmineProjectWorkflows::Services::PermissionFields).
#
# A plugin adds its names in its own init.rb, in whichever order the plugins
# load and without depending on this one:
#
#   %w[impact_id urgency_id].each { |name| Rails.configuration.x.project_workflow_permission_fields[name] = true }
#
# A registered name is offered only when WorkflowPermission's own
# validate_field_name accepts it (INV-2): registering is not enough.
module ExtensionFieldSpec
  FIELD = 'extension_spec_id'

  class << self
    attr_accessor :accepted
  end

  module Validation
    protected

    def validate_field_name
      return if ExtensionFieldSpec.accepted && field_name == ExtensionFieldSpec::FIELD

      super
    end
  end
end

RSpec.shared_context 'with an extension field registered' do
  around do |example|
    WorkflowPermission.prepend(ExtensionFieldSpec::Validation)
    previous = Rails.configuration.x.project_workflow_permission_fields.dup
    Rails.configuration.x.project_workflow_permission_fields = ActiveSupport::OrderedOptions.new
    Rails.configuration.x.project_workflow_permission_fields[ExtensionFieldSpec::FIELD] = true
    ExtensionFieldSpec.accepted = true
    example.run
  ensure
    ExtensionFieldSpec.accepted = false
    Rails.configuration.x.project_workflow_permission_fields = previous
  end
end

describe 'RedmineProjectWorkflows::Services::PermissionFields' do
  include_context 'with an extension field registered'

  let(:service) { RedmineProjectWorkflows::Services::PermissionFields }

  it 'offers a registered name the model accepts, with a label' do
    expect(service.extra_names).to eq([ExtensionFieldSpec::FIELD])
    expect(service.for_trackers([Tracker.first]).last).to eq([ExtensionFieldSpec::FIELD, 'Extension spec'])
  end

  it 'takes a registration made with the documented one-liner, whatever was read before' do
    Rails.configuration.x.project_workflow_permission_fields = ActiveSupport::OrderedOptions.new
    expect(service.extra_names).to eq([])

    [ExtensionFieldSpec::FIELD].each { |name| Rails.configuration.x.project_workflow_permission_fields[name] = true }

    expect(service.extra_names).to eq([ExtensionFieldSpec::FIELD])
  end

  it 'offers nothing extra when nothing is registered' do
    Rails.configuration.x.project_workflow_permission_fields = nil

    expect(service.extra_names).to eq([])
  end

  it 'does not offer a registered name the model refuses (INV-2)' do
    ExtensionFieldSpec.accepted = false

    expect(service.extra_names).to eq([])
  end

  it 'ignores registered names that are not plain identifiers, core fields or custom field ids' do
    Rails.configuration.x.project_workflow_permission_fields =
      ["x\n5", '5', 'Subject', 'subject', :extension_spec_id, ExtensionFieldSpec::FIELD]

    expect(service.extra_names).to eq([ExtensionFieldSpec::FIELD])
  end
end

describe ProjectWorkflowsController, type: :controller do
  include_context 'with an extension field registered'
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :issues

  render_views

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:params_for) { { project_id: project.id, tracker_id: tracker.id, role_id: role.id } }

  before do
    role.add_permission!(:manage_project_workflow_rules)
    @request.session[:user_id] = 2
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
  end

  it 'shows the registered field as a row of the project matrix' do
    get :permissions, params: params_for

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Extension spec')
    expect(response.body).to include("permissions[#{status.id}][#{ExtensionFieldSpec::FIELD}]")
  end

  # Not a regression test for this change -- the writer already took a name
  # the model accepts (decision q3) -- but the behaviour round 6 asks for:
  # saved for this project only, enforced there, the generic rule and another
  # project untouched.
  it 'saves a project rule for it, enforced in that project only' do
    WorkflowPermission.where(project_id: [nil, project.id], tracker_id: tracker.id, role_id: role.id).delete_all
    WorkflowPermission.create!(project_id: nil, tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
                               field_name: ExtensionFieldSpec::FIELD, rule: 'required')

    patch :update_permissions,
          params: params_for.merge(permissions: { status.id.to_s => { ExtensionFieldSpec::FIELD => 'readonly' } })

    expect(WorkflowPermission.where(project_id: project.id, tracker_id: tracker.id, role_id: role.id,
                                    field_name: ExtensionFieldSpec::FIELD).pluck(:rule)).to eq(['readonly'])
    expect(WorkflowPermission.where(project_id: nil, tracker_id: tracker.id, role_id: role.id,
                                    field_name: ExtensionFieldSpec::FIELD).pluck(:rule)).to eq(['required'])

    user = User.find(2)
    issue = Issue.find_by!(project_id: project.id, tracker_id: tracker.id, status_id: status.id)
    expect(issue.send(:workflow_rule_by_attribute, user)[ExtensionFieldSpec::FIELD]).to eq('readonly')

    # The same user, with the same single role, in a project that follows the
    # generic workflow: the generic rule, not the project's.
    elsewhere = Issue.where(tracker_id: tracker.id).where.not(project_id: project.id).first!
    elsewhere.update_column(:status_id, status.id) # rubocop:disable Rails/SkipsModelValidations -- a fixture, not the code under test
    elsewhere.project.trackers << tracker unless elsewhere.project.trackers.include?(tracker)
    Member.where(user_id: user.id, project_id: elsewhere.project_id).destroy_all
    Member.create!(principal: user, project: elsewhere.project, roles: [role])
    expect(elsewhere.reload.send(:roles_for_workflow, user)).to eq([role])
    expect(elsewhere.send(:workflow_rule_by_attribute, user)[ExtensionFieldSpec::FIELD]).to eq('required')
  end

  it 'counts the field as offered on the comparison screen' do
    get :compare, params: params_for.merge(rule_type: ProjectWorkflowScope::PERMISSIONS)

    expect(assigns(:offered_field_names)).to include(ExtensionFieldSpec::FIELD)
  end
end

describe ProjectWorkflowRulesController, type: :controller do
  include_context 'with an extension field registered'
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  render_views

  before { @request.session[:user_id] = 1 }

  it 'shows the registered field as a row of the administration matrix' do
    get :permissions, params: { tracker_id: [trackers(:trackers_001).id.to_s], role_id: [roles(:roles_001).id.to_s],
                                project_id: [projects(:projects_001).id.to_s] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Extension spec')
    expect(response.body).to include("[#{ExtensionFieldSpec::FIELD}]")
  end
end

# The real neighbour, on a host that has it and has added the registration line
# docs/REDMINE7-MIGRATION.md gives for redmine_itil_priority's init.rb.
describe 'redmine_itil_priority on this plugin\'s matrices' do
  it 'offers Impact and Urgency, labelled as that plugin labels them' do
    skip 'redmine_itil_priority is not installed on this host' unless Redmine::Plugin.installed?(:redmine_itil_priority)

    fields = RedmineProjectWorkflows::Services::PermissionFields.for_trackers([Tracker.first]).to_h
    expect(fields.keys).to include('impact_id', 'urgency_id')
    expect(fields['impact_id']).to eq(I18n.t(:field_impact))
  end
end
