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

  describe 'generic write path' do
    it 'accepts a rule value that core validation rejects' do
      expect {
        WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                                   old_status_id: s1.id, field_name: 'due_date', rule: 'bogus')
      }.to raise_error(ActiveRecord::RecordInvalid)

      WorkflowPermission.replace_permissions([tracker], [role],
                                             { s1.id.to_s => { 'due_date' => 'bogus' } })
      row = WorkflowPermission.where(project_id: nil, field_name: 'due_date').first
      expect(row&.rule).to eq('bogus')
    end

    it 'accepts a field name that does not exist' do
      WorkflowPermission.replace_permissions([tracker], [role],
                                             { s1.id.to_s => { 'niet_bestaand_veld' => 'readonly' } })
      expect(WorkflowPermission.pluck(:field_name)).to include('niet_bestaand_veld')
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

  describe 'copying to the generic workflow only' do
    it 'ignores the source project and copies generic to generic' do
      target_role = roles(:roles_002)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: project.id)
      post :duplicate, params: {
        source_project_id: project.id.to_s, source_tracker_id: tracker.id.to_s,
        source_role_id: role.id.to_s, target_tracker_ids: [tracker.id.to_s],
        target_role_ids: [target_role.id.to_s], target_project_ids: ['global']
      }
      copied = WorkflowTransition.where(project_id: nil, role_id: target_role.id).count
      expect(copied).to eq(0)
    end
  end

  describe 'invalid copy target' do
    it 'raises DoubleRenderError instead of reporting a validation error' do
      begin
        post :duplicate, params: {
          source_tracker_id: tracker.id.to_s, source_role_id: role.id.to_s,
          target_tracker_ids: [tracker.id.to_s], target_role_ids: [roles(:roles_002).id.to_s],
          target_project_ids: ['999999']
        }
        raise 'expected an error'
      rescue AbstractController::DoubleRenderError => e
        expect(e).to be_a(AbstractController::DoubleRenderError)
      end
    end

    it 'does the same for a non-numeric project id' do
      expect {
        post :duplicate, params: {
          source_tracker_id: tracker.id.to_s, source_role_id: role.id.to_s,
          target_tracker_ids: [tracker.id.to_s], target_role_ids: [roles(:roles_002).id.to_s],
          target_project_ids: ['abc']
        }
      }.to raise_error(AbstractController::DoubleRenderError)
    end
  end
end

describe WorkflowsController, type: :controller do
  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules

  before { @request.session[:user_id] = 1 }

  # Since Redmine 6.0 the multiselect toggle is an SVG sprite. Core renders
  # sprite_icon('') inside the span; the plugin's partial renders an empty span.
  # Core's toggleMultiSelectIconInit() then calls updateSVGIcon(undefined, ...),
  # which throws a TypeError and aborts the remaining $(document).ready work.
  it "renders a toggle-multiselect span without the sprite core expects" do
    get :edit, params: { role_id: [roles(:roles_001).id], tracker_id: [trackers(:trackers_001).id],
                         project_id: ['global'], used_statuses_only: '0' }
    spans = response.body.scan(%r{<span class="toggle-multiselect[^"]*">(.*?)</span>}m)
    without_svg = spans.count { |(inner)| !inner.include?('<svg') }

    expect(spans.size).to be >= 3
    expect(without_svg).to be >= 1
  end
end
