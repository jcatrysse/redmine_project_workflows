# frozen_string_literal: true

class AddProjectIdToWorkflows < ActiveRecord::Migration[6.1]
  def up
    add_column :workflows, :project_id, :integer

    add_index :workflows,
              %i[project_id role_id tracker_id old_status_id type],
              name: 'index_workflows_on_project_role_tracker_old_status_type'
    add_index :workflows,
              %i[project_id tracker_id role_id type],
              name: 'index_workflows_on_project_tracker_role_type'
  end

  def down
    say_with_time 'Removing project-specific workflow rules' do
      execute("DELETE FROM #{WorkflowRule.table_name} WHERE project_id IS NOT NULL")
    end

    remove_index :workflows, name: 'index_workflows_on_project_role_tracker_old_status_type'
    remove_index :workflows, name: 'index_workflows_on_project_tracker_role_type'
    remove_column :workflows, :project_id
  end
end
