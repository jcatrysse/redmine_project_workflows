# frozen_string_literal: true

require_relative '../spec_helper'

# WP14, audit finding F03.
#
# Deleting an issue status removes every workflow rule that names it, in core.
# The plugin's scope rows survive that, and a scope whose rules have all gone is
# an own *empty* workflow -- which for transitions permits no change of status
# at all. The administrator is told; nothing is cleaned up, because deleting the
# emptied scope would return the project to the generic workflow and that is a
# decision the project made and nobody undid (INV-3).
#
# Every example here is red on the code before this patch: it set no flash at
# all on a successful deletion.
describe IssueStatusesController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:survivor) { issue_statuses(:issue_statuses_002) }
  # A status of this spec's own, so that the deletion cannot be refused by
  # core's check_integrity over a fixture issue another spec file loaded.
  let(:doomed) { IssueStatus.create!(name: 'Zzz-temp') }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    @request.session[:user_id] = 1
  end

  def own_rule_naming(status, target_project: project)
    give_own_workflow(target_project, tracker, role)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: target_project.id,
                               old_status_id: status.id, new_status_id: survivor.id)
  end

  describe 'DELETE destroy' do
    it 'warns that a project workflow was left with no rules' do
      own_rule_naming(doomed)

      delete :destroy, params: { id: doomed.id }

      expect(IssueStatus.exists?(doomed.id)).to be(false)
      expect(flash[:warning]).to be_present
      # The message up to where the link is interpolated, so that the assertion
      # is about what the administrator is told rather than about the markup of
      # one anchor.
      expected = I18n.t(:warning_project_workflow_status_deleted_emptied, count: 1, link: 'INVENTORY')
      expect(flash[:warning]).to include(expected.split('INVENTORY').first)
      expect(flash[:warning]).to include(I18n.t(:label_project_workflow_inventory))
    end

    # The whole point of warning rather than cleaning up (INV-3): the project
    # still runs its own workflow here, it is simply an empty one now.
    it 'leaves the scope exactly where it was' do
      own_rule_naming(doomed)

      delete :destroy, params: { id: doomed.id }

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'links to the inventory, filtered to the projects that were affected' do
      own_rule_naming(doomed)
      own_rule_naming(doomed, target_project: other_project)

      delete :destroy, params: { id: doomed.id }

      expect(flash[:warning]).to include("project_id%5B%5D=#{project.id}")
      expect(flash[:warning]).to include("project_id%5B%5D=#{other_project.id}")
      expect(flash[:warning]).to include('deviations_only=1')
    end

    it 'says nothing when the deletion emptied no project workflow' do
      own_rule_naming(survivor)

      delete :destroy, params: { id: doomed.id }

      expect(IssueStatus.exists?(doomed.id)).to be(false)
      expect(flash[:warning]).to be_nil
    end

    it 'says nothing about the generic workflow' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: doomed.id, new_status_id: survivor.id)

      delete :destroy, params: { id: doomed.id }

      expect(flash[:warning]).to be_nil
    end

    # Core refuses to delete a status a tracker uses as its default, rescues the
    # exception and reports it. Nothing was emptied, so nothing may be claimed.
    it 'says nothing when the deletion was refused' do
      own_rule_naming(doomed)
      Tracker.where(id: tracker.id).update_all(default_status_id: doomed.id) # rubocop:disable Rails/SkipsModelValidations

      delete :destroy, params: { id: doomed.id }

      expect(IssueStatus.exists?(doomed.id)).to be(true)
      expect(flash[:error]).to be_present
      expect(flash[:warning]).to be_nil
    end

    it 'is still administrator-only' do
      @request.session[:user_id] = 2
      own_rule_naming(doomed)

      delete :destroy, params: { id: doomed.id }

      expect(response).to have_http_status(:forbidden)
      expect(IssueStatus.exists?(doomed.id)).to be(true)
    end

    it 'reports a status that does not exist the way core does' do
      delete :destroy, params: { id: 'not-a-status' }

      expect(flash[:error]).to be_present
      expect(flash[:warning]).to be_nil
    end
  end
end
