# frozen_string_literal: true
#
# CHARACTERIZATION TESTS - these lock in behaviour that is currently WRONG.
#
# Every example here passes today and documents a known defect. They exist so
# that the fixes can be made deliberately: when a defect is repaired, its
# example must be inverted (or deleted), never "made green" again.
#
# Do not read these as a specification of intended behaviour.
#
require_relative '../spec_helper'

describe WorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles,
           :enabled_modules, :issue_categories, :enumerations

  let(:project) { projects(:projects_001) }
  let(:role)    { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }

  before do
    @request.session[:user_id] = 1
    WorkflowRule.delete_all
  end

  describe 'workflow summary page' do
    it 'counts project rules towards the generic totals' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: nil)
      get :index
      generic_only = assigns(:workflow_counts)[[tracker.id, role.id]]

      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: project.id)
      get :index
      with_project = assigns(:workflow_counts)[[tracker.id, role.id]]
      expect(generic_only).to eq(1)
      expect(with_project).to eq(2)   # only one generic rule exists
    end
  end

  describe 'Tracker#issue_status_ids' do
    it 'leaks a project-only status into the global tracker list' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: project.id)
      ids = Tracker.find(tracker.id).issue_status_ids
      expect(ids).to include(s2.id)
    end
  end

  describe 'Project#rolled_up_statuses' do
    it 'returns nothing for a project without members, where core returns the used statuses' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: nil)
      empty = Project.create!(name: 'No members', identifier: 'no-members')
      empty.trackers = [tracker]
      empty.save!
      core_would_give = WorkflowTransition.where(tracker_id: empty.rolled_up_trackers.map(&:id))
                                          .where('old_status_id <> new_status_id').count
      expect(empty.rolled_up_statuses.to_a).to eq([])
      expect(core_would_give).to be_positive
    end
  end

  describe 'used statuses filter' do
    it 'falls back to every status for a project without rules of its own' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: nil)
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '1' }
      shown = assigns(:statuses).size
      expect(shown).to eq(IssueStatus.count)
    end
  end
end
