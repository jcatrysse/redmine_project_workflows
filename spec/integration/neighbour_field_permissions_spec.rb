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
# A stand-in for a neighbour's validate_field_name extension. Prepending is
# permanent for the process, so the extension is inert unless switched on.
module NeighbourFieldSpec
  FIELD = 'neighbour_spec_id'

  class << self
    attr_accessor :enabled
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

  before(:all) { WorkflowPermission.prepend(NeighbourFieldSpec::Validation) }

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

  it 'still drops a custom field id that names no custom field' do
    WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id).delete_all

    WorkflowPermission.replace_permissions([tracker], [role], status.id.to_s => { '999999' => 'readonly' })

    expect(WorkflowPermission.where(tracker_id: tracker.id, role_id: role.id)).to be_empty
  end

  # The real neighbour, on a host that has it (the combined GEOxyz host).
  it 'shows and saves redmine_itil_priority Impact and Urgency on the generic screen', type: :request do
    skip 'redmine_itil_priority is not installed on this host' unless Redmine::Plugin.installed?(:redmine_itil_priority)

    admin = User.find(1)
    allow(User).to receive(:current).and_return(admin)
    WorkflowPermission.replace_permissions([tracker], [role], status.id.to_s => { 'impact_id' => 'readonly' })
    expect(WorkflowPermission.where(project_id: nil, tracker_id: tracker.id, role_id: role.id, field_name: 'impact_id')
                             .pluck(:rule)).to eq(['readonly'])

    controller = WorkflowsController.new
    expect(controller.class.instance_method(:permissions).owner.name.to_s).not_to start_with('RedmineProjectWorkflows')
  end
end
