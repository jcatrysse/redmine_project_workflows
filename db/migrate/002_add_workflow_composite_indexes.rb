# frozen_string_literal: true

class AddWorkflowCompositeIndexes < ActiveRecord::Migration[6.1]
  def up
    add_index :workflows,
              %i[project_id tracker_id role_id old_status_id type],
              name: 'index_workflows_on_project_tracker_role_old_status_type' \
              unless index_exists?(
                :workflows,
                %i[project_id tracker_id role_id old_status_id type],
                name: 'index_workflows_on_project_tracker_role_old_status_type'
              )

    add_index :workflows,
              %i[project_id tracker_id role_id old_status_id field_name type],
              name: 'index_workflows_on_project_tracker_role_old_status_field_type' \
              unless index_exists?(
                :workflows,
                %i[project_id tracker_id role_id old_status_id field_name type],
                name: 'index_workflows_on_project_tracker_role_old_status_field_type'
              )
  end

  def down
    remove_index :workflows, name: 'index_workflows_on_project_tracker_role_old_status_type' \
      if index_exists?(:workflows, name: 'index_workflows_on_project_tracker_role_old_status_type')
    remove_index :workflows, name: 'index_workflows_on_project_tracker_role_old_status_field_type' \
      if index_exists?(:workflows, name: 'index_workflows_on_project_tracker_role_old_status_field_type')
  end
end
