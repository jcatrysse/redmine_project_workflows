# frozen_string_literal: true

require_relative '../spec_helper'

# external F06. There is no unique index on `workflows` and there cannot be a
# portable one, so what the plugin can promise is that its own writers never
# produce a duplicate: saving the same matrix twice is the same as saving it
# once. What is left -- two administrators saving concurrently -- is repaired by
# WorkflowRule.delete_duplicate_rules!, which is exercised here too.
describe 'Repeating a workflow write' do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  let(:transitions) do
    {
      old_status.id.to_s => {
        new_status.id.to_s => { 'always' => '1', 'author' => '1', 'assignee' => '0' }
      }
    }
  end

  let(:permissions) do
    { old_status.id.to_s => { 'due_date' => 'required' } }
  end

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def rows_for(project_id)
    WorkflowRule.where(project_id: project_id).order(:id).pluck(
      :type, :tracker_id, :role_id, :old_status_id, :new_status_id, :author, :assignee, :field_name, :rule
    )
  end

  describe 'transitions' do
    it 'writes the same rows the second time, for the generic workflow' do
      WorkflowTransition.replace_transitions([tracker], [role], transitions)
      first = rows_for(nil)

      WorkflowTransition.replace_transitions([tracker], [role], transitions)

      expect(first).not_to be_empty
      expect(rows_for(nil)).to eq(first)
    end

    it 'writes the same rows the second time, for a project' do
      writer = RedmineProjectWorkflows::Services::TransitionWriter
      writer.replace_transitions_for_project_id(project.id, [tracker], [role], transitions)
      first = rows_for(project.id)

      writer.replace_transitions_for_project_id(project.id, [tracker], [role], transitions)

      expect(first).not_to be_empty
      expect(rows_for(project.id)).to eq(first)
    end

    it 'records the decision once, not once per save' do
      writer = RedmineProjectWorkflows::Services::TransitionWriter
      writer.replace_transitions_for_project_id(project.id, [tracker], [role], transitions)
      scope = ProjectWorkflowScope.find_by!(
        project_id: project.id, tracker_id: tracker.id, role_id: role.id,
        rule_type: ProjectWorkflowScope::TRANSITIONS
      )

      expect { writer.replace_transitions_for_project_id(project.id, [tracker], [role], transitions) }
        .not_to(change { ProjectWorkflowScope.count })
      expect(scope.reload.created_at).to eq(scope.created_at)
    end
  end

  describe 'permissions' do
    it 'writes the same rows the second time, for the generic workflow' do
      WorkflowPermission.replace_permissions([tracker], [role], permissions)
      first = rows_for(nil)

      WorkflowPermission.replace_permissions([tracker], [role], permissions)

      expect(first).not_to be_empty
      expect(rows_for(nil)).to eq(first)
    end

    it 'writes the same rows the second time, for a project' do
      writer = RedmineProjectWorkflows::Services::PermissionWriter
      writer.replace_permissions_for_project_id(project.id, [tracker], [role], permissions)
      first = rows_for(project.id)

      writer.replace_permissions_for_project_id(project.id, [tracker], [role], permissions)

      expect(first).not_to be_empty
      expect(rows_for(project.id)).to eq(first)
    end
  end

  describe 'WorkflowRule.delete_duplicate_rules!' do
    def transition_row(project_id)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: new_status.id,
        project_id: project_id, author: false, assignee: false
      )
    end

    it 'keeps the oldest of a set of duplicates' do
      kept = transition_row(nil)
      transition_row(nil)
      transition_row(nil)

      expect(WorkflowRule.delete_duplicate_rules!).to eq(2)
      expect(WorkflowTransition.where(project_id: nil).pluck(:id)).to eq([kept.id])
    end

    it 'sweeps the generic rows and the project rows separately' do
      generic = transition_row(nil)
      transition_row(nil)
      owned = transition_row(project.id)
      transition_row(project.id)

      expect(WorkflowRule.delete_duplicate_rules!).to eq(2)
      expect(WorkflowTransition.where(project_id: nil).pluck(:id)).to eq([generic.id])
      expect(WorkflowTransition.where(project_id: project.id).pluck(:id)).to eq([owned.id])
    end

    it 'does not confuse a project row with the generic row it was copied from' do
      transition_row(nil)
      transition_row(project.id)

      expect(WorkflowRule.delete_duplicate_rules!).to eq(0)
      expect(WorkflowTransition.count).to eq(2)
    end

    it 'leaves two field permissions that disagree alone' do
      WorkflowPermission.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: old_status.id,
        field_name: 'due_date', rule: 'required', project_id: nil
      )
      WorkflowPermission.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: old_status.id,
        field_name: 'due_date', rule: 'readonly', project_id: nil
      )

      # A contradiction, not a duplicate. Silently picking one of the two would
      # be answering a question only the administrator can answer.
      expect(WorkflowRule.delete_duplicate_rules!).to eq(0)
      expect(WorkflowPermission.count).to eq(2)
    end

    it 'does nothing to a table with no duplicates' do
      transition_row(nil)
      transition_row(project.id)
      WorkflowPermission.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: old_status.id,
        field_name: 'due_date', rule: 'required', project_id: project.id
      )

      expect { WorkflowRule.delete_duplicate_rules! }.not_to(change { WorkflowRule.count })
    end
  end
end
