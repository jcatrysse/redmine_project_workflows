# frozen_string_literal: true

require_relative '../spec_helper'

describe WorkflowsHelper, type: :helper do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:field_name) { 'subject' }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  before do
    helper.instance_variable_set(:@roles, [role])
    helper.instance_variable_set(:@trackers, [tracker])
    helper.instance_variable_set(:@projects_for_update, [project, other_project])
  end

  it 'treats full project coverage as a checked transition' do
    html = helper.transition_tag(2, status, new_status, 'always')

    expect(html).to include('type="checkbox"')
  end

  it 'uses no-change when not all projects share the same permission' do
    permissions = {
      status.id => {
        field_name => ['readonly']
      }
    }

    html = helper.field_permission_tag(permissions, status, field_name, [role])

    expect(html).to include('no_change')
  end

  it 'treats full project and global coverage as a checked transition' do
    helper.instance_variable_set(:@global_selected, true)

    html = helper.transition_tag(3, status, new_status, 'always')

    expect(html).to include('type="checkbox"')
  end

  # WP1. Three states have to stay tellable apart (INV-3), and a mixed selection
  # names only the states it actually contains -- a zero count is noise.
  describe '#project_workflow_scope_state_tag' do
    def state_for(projects)
      RedmineProjectWorkflows::Services::ScopeState.new(
        project_ids: projects, tracker_ids: [tracker], role_ids: [role],
        rule_type: ProjectWorkflowScope::TRANSITIONS
      )
    end

    before do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
    end

    it 'names a uniform selection in words' do
      give_own_workflow(project, tracker, role)

      expect(helper.project_workflow_scope_state_tag(state_for([project])))
        .to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_own_empty)))
    end

    it 'leaves a zero count out of a mixed selection' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: status.id, new_status_id: new_status.id)
      give_own_workflow(other_project, tracker, role)

      html = helper.project_workflow_scope_state_tag(state_for([project, other_project]))

      expect(html).to include(I18n.t(:label_project_workflow_count_own, count: 1))
      expect(html).to include(I18n.t(:label_project_workflow_count_own_empty, count: 1))
      # Nothing in this selection inherits, so nothing says so.
      expect(html).not_to include(I18n.t(:label_project_workflow_count_inherits, count: 0))
    end
  end
end
