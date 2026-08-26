# frozen_string_literal: true

# The scope table (ADR-001). One row per (project, tracker, role, rule type)
# records the *decision* that the project runs its own workflow for that
# combination, independent of whether any rule rows exist. Without it the three
# states of INV-3 -- inherits / own workflow / own empty workflow -- cannot be
# told apart in the database.
class CreateProjectWorkflowScopes < ActiveRecord::Migration[6.1]
  # The columns are declared :integer rather than the Rails default :bigint on
  # purpose. Redmine's own primary keys are 4-byte integers, and MySQL refuses a
  # foreign key whose column width differs from the column it references.
  def up
    create_table :project_workflow_scopes do |t|
      t.integer :project_id, null: false
      t.integer :tracker_id, null: false
      t.integer :role_id, null: false
      t.string :rule_type, null: false, limit: 20
      t.integer :created_by_id
      t.integer :updated_by_id
      t.timestamps null: false
    end

    add_index :project_workflow_scopes,
              %i[project_id tracker_id role_id rule_type],
              unique: true,
              name: 'index_project_workflow_scopes_unique'
    add_index :project_workflow_scopes,
              %i[project_id rule_type],
              name: 'index_project_workflow_scopes_on_project_and_rule_type'
    add_index :project_workflow_scopes,
              %i[tracker_id role_id rule_type],
              name: 'index_project_workflow_scopes_on_tracker_role_rule_type'

    add_foreign_key :project_workflow_scopes, :projects, column: :project_id, on_delete: :cascade
    add_foreign_key :project_workflow_scopes, :trackers, column: :tracker_id, on_delete: :cascade
    add_foreign_key :project_workflow_scopes, :roles, column: :role_id, on_delete: :cascade
    add_foreign_key :project_workflow_scopes, :users, column: :created_by_id, on_delete: :nullify
    add_foreign_key :project_workflow_scopes, :users, column: :updated_by_id, on_delete: :nullify

    backfill
  end

  def down
    drop_table :project_workflow_scopes
  end

  private

  # Existing installations decided "this project overrides" by the presence of
  # rule rows. Every (project, tracker, role) that has rows therefore gets a
  # scope of the matching type, so behaviour after the migration is exactly the
  # behaviour before it.
  #
  # Written as one INSERT ... SELECT rather than through ActiveRecord: it is a
  # set operation, it does not need to load a row into memory, and it must not
  # depend on a model class that later migrations may reshape. The EXISTS
  # guards keep the foreign keys added above satisfiable on a database that
  # carries orphaned rule rows.
  #
  # The timestamps are CURRENT_TIMESTAMP rather than a quoted Ruby Time:
  # PostgreSQL does not cast a text literal to a timestamp inside a SELECT list,
  # and the casts that would work are spelled differently on MySQL. Rails puts
  # every supported adapter's session in UTC, so all three agree on the value.
  def backfill
    workflows = WorkflowRule.table_name

    { 'WorkflowTransition' => 'transitions', 'WorkflowPermission' => 'permissions' }.each do |sti_type, rule_type|
      say_with_time "Backfilling #{rule_type} scopes" do
        execute(<<~SQL.squish)
          INSERT INTO project_workflow_scopes
            (project_id, tracker_id, role_id, rule_type, created_at, updated_at)
          SELECT DISTINCT w.project_id, w.tracker_id, w.role_id,
                          #{connection.quote(rule_type)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM #{workflows} w
          WHERE w.project_id IS NOT NULL
            AND w.type = #{connection.quote(sti_type)}
            AND EXISTS (SELECT 1 FROM projects p WHERE p.id = w.project_id)
            AND EXISTS (SELECT 1 FROM trackers t WHERE t.id = w.tracker_id)
            AND EXISTS (SELECT 1 FROM roles r WHERE r.id = w.role_id)
        SQL
      end
    end
  end
end
