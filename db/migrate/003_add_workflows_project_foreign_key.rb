# frozen_string_literal: true

class AddWorkflowsProjectForeignKey < ActiveRecord::Migration[6.1]
  def up
    return unless column_exists?(:workflows, :project_id)
    return if foreign_key_exists?(:workflows, :projects, column: :project_id)

    execute <<~SQL.squish
      DELETE FROM workflows
      WHERE project_id IS NOT NULL
      AND project_id NOT IN (SELECT id FROM projects)
    SQL

    add_foreign_key :workflows, :projects, column: :project_id, on_delete: :cascade
  end

  def down
    return unless foreign_key_exists?(:workflows, :projects, column: :project_id)

    remove_foreign_key :workflows, column: :project_id
  end
end
