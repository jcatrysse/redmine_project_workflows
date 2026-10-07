# frozen_string_literal: true

require_relative '../spec_helper'

# Decision q3 of docs/REDMINE7-MIGRATION.md (Jan, 2026-10-07): another plugin
# that adds fields to Administration -> Workflow -> Fields permissions -- as
# redmine_itil_priority does for Impact and Urgency, by prepending
# WorkflowsController#permissions and extending
# WorkflowPermission#validate_field_name -- must keep working with this plugin
# installed (finding C2).
#
# It did not, for two reasons, both in this plugin:
# - the plugin replaced WorkflowsController#permissions without `super`, so a
#   neighbour prepended *before* it (alphabetical load order) never ran;
# - PermissionWriter accepted only core fields and custom field ids, so a field
#   the model itself accepts was dropped on save.
#
# The action is core's again; what made the plugin replace it -- a read of the
# workflows table without a project_id predicate (INV-4) -- is answered by
# scoping WorkflowPermission.rules_by_status_id, its only caller's query.
#
# Stand-ins for a neighbour: a validate_field_name extension and a wrapper of
# the generic Fields permissions action that adds the field's row. Prepending is
# permanent for the process, so both are inert unless switched on.
module NeighbourFieldSpec
  FIELD = 'neighbour_spec_id'

  class << self
    attr_accessor :enabled
  end

  module Rows
    def permissions
      super
      @fields += [[NeighbourFieldSpec::FIELD, 'Neighbour spec field']] if NeighbourFieldSpec.enabled && @fields
    end
  end

  module Validation
    private

    def validate_field_name
      return if NeighbourFieldSpec.enabled && field_name == NeighbourFieldSpec::FIELD

      super
    end
  end
end

describe 'Fields permissions with a neighbour plugin adding a field' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }

  before(:all) do
    WorkflowPermission.prepend(NeighbourFieldSpec::Validation)
    WorkflowsController.prepend(NeighbourFieldSpec::Rows)
  end

  around do |example|
    NeighbourFieldSpec.enabled = true
    example.run
  ensure
    NeighbourFieldSpec.enabled = false
  end

  it 'leaves WorkflowsController#permissions to core, so a neighbour wrapping it runs' do
    patch = RedmineProjectWorkflows::Patches::WorkflowsControllerPatch
    expect(patch.instance_methods(false) + patch.private_instance_methods(false)).not_to include(:permissions)
  end

  it 'answers rules_by_status_id with the generic workflow only (INV-4)' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
                               field_name: 'subject', rule: 'readonly', project_id: nil)
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
                               field_name: 'due_date', rule: 'required', project_id: project.id)

    expect(WorkflowPermission.rules_by_status_id([tracker], [role]))
      .to eq(status.id => { 'subject' => ['readonly'] })
  end

  it 'saves a generic rule for a field the model accepts through a neighbour' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all

    WorkflowPermission.replace_permissions([tracker], [role],
                                           status.id.to_s => { NeighbourFieldSpec::FIELD => 'required' })

    expect(WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id, project_id: nil)
                             .pluck(:field_name, :rule)).to eq([[NeighbourFieldSpec::FIELD, 'required']])
  end

  it 'still drops a field name nothing accepts (INV-2)' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all
    NeighbourFieldSpec.enabled = false

    WorkflowPermission.replace_permissions([tracker], [role],
                                           status.id.to_s => { NeighbourFieldSpec::FIELD => 'required',
                                                               'no_such_field' => 'readonly' })

    expect(WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id)).to be_empty
  end

  # Core's own check is line-anchored (/^\d+$/), so a name with one line of
  # digits in it passes core; the writer must not ask core about such a name.
  it 'drops a field name that is not a plain identifier, whatever core would say (INV-2)' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all

    WorkflowPermission.replace_permissions([tracker], [role],
                                           status.id.to_s => { "5\n<svg onload=x>" => 'readonly', "\n5" => 'readonly',
                                                               'Subject' => 'readonly', ' subject' => 'readonly' })

    expect(WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id)).to be_empty
  end

  it 'still drops a custom field id that names no custom field' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all

    WorkflowPermission.replace_permissions([tracker], [role], status.id.to_s => { '999999' => 'readonly' })

    expect(WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id)).to be_empty
  end

  # Pinned rather than decided: giving a project its own field permissions as a
  # copy of the generic ones carries a neighbour's rule along, so the project
  # behaves exactly as before the takeover. The plugin's own project matrices do
  # not offer that field, so the rule is visible there only through the
  # comparison screen (open question for Jan in docs/REDMINE7-MIGRATION.md).
  it 'carries a generic rule for a neighbour field into a project that takes its workflow over' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all
    WorkflowPermission.replace_permissions([tracker], [role],
                                           status.id.to_s => { NeighbourFieldSpec::FIELD => 'readonly' })

    RedmineProjectWorkflows::Services::ScopeWriter.enable(
      project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
      rule_type: ProjectWorkflowScope::PERMISSIONS, copy_generic: true, user: User.find(1)
    )

    expect(WorkflowPermission.where(project_id: project.id, tracker_id: tracker.id, role_id: role.id)
                             .pluck(:field_name, :rule)).to eq([[NeighbourFieldSpec::FIELD, 'readonly']])
  end

  # The real neighbour, on a host that has it (the combined GEOxyz host); the
  # stand-ins cover every other host.
  it 'saves redmine_itil_priority Impact on the generic workflow where that plugin is installed' do
    skip 'redmine_itil_priority is not installed on this host' unless Redmine::Plugin.installed?(:redmine_itil_priority)

    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all
    WorkflowPermission.replace_permissions([tracker], [role], status.id.to_s => { 'impact_id' => 'readonly' })

    expect(WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).pluck(:project_id, :field_name, :rule))
      .to eq([[nil, 'impact_id', 'readonly']])
  end
end

describe WorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  render_views

  around do |example|
    NeighbourFieldSpec.enabled = true
    example.run
  ensure
    NeighbourFieldSpec.enabled = false
  end

  before do
    WorkflowPermission.prepend(NeighbourFieldSpec::Validation)
    WorkflowsController.prepend(NeighbourFieldSpec::Rows)
    @request.session[:user_id] = 1
  end

  # Coverage of the rendering, not the regression test: a module prepended here
  # lands in front of the plugin's patch, so it ran on the old code too. The
  # load order that broke (neighbour behind the plugin) is what the first
  # example of the block above pins.
  it "renders the row a neighbour's wrapper adds to the generic Fields permissions screen" do
    get :permissions, params: { role_id: [roles(:roles_001).id.to_s], tracker_id: [trackers(:trackers_001).id.to_s] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Neighbour spec field')
    expect(response.body).to include("[#{NeighbourFieldSpec::FIELD}]")
  end
end
