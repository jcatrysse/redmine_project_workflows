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
  # The timestamps are built in Ruby, and the comment that used to stand here was
  # wrong in both halves (finding F09).
  #
  # It said CURRENT_TIMESTAMP was safe because "Rails puts every supported
  # adapter's session in UTC, so all three agree on the value". True of
  # PostgreSQL, whose adapter sets the session timezone to UTC when
  # default_timezone is :utc; false of MySQL and MariaDB, whose
  # AbstractMysqlAdapter#configure_connection sets sql_auto_is_null, wait_timeout
  # and sql_mode and no time_zone at all, in Rails 6.1, 7.2 and 8.0. So on six of
  # the nine supported cells these columns were the server's local time, read
  # back as if it were UTC.
  #
  # It also said PostgreSQL "does not cast a text literal to a timestamp inside a
  # SELECT list". Measured on PostgreSQL 16: a bare quoted literal in the SELECT
  # list of an INSERT ... SELECT is coerced to the target timestamp column with no
  # cast at all, which is why the plain literal below is what is written.
  #
  # It used to be the standard `TIMESTAMP '...'` type-keyword form, on the
  # argument that it "says what it means" -- true, and it says it in a dialect
  # SQLite does not have. There the whole statement fails with
  # `no such column: TIMESTAMP`, migrations 001..003 have already committed, and
  # the installation is left carrying `workflows.project_id` with no scope table
  # under it, which makes every issue page a 500. Redmine ships SQLite support in
  # its own Gemfile and `config/database.yml.example`, and nothing here declares
  # it unsupported (finding F02 of 2026-08-28-claude-audit). The plain literal is
  # accepted by all four, and the whole suite passes on SQLite with it.
  #
  # Changing a shipped migration is a judgement call, and this is the reasoning:
  # an installation that has already run 004 keeps whatever it wrote, and this
  # only affects installations that migrate from here on. That divergence is
  # harmless -- project_workflows_helper.rb returns early when updated_by is
  # blank, so a backfilled scope displays no time at all either way -- while
  # leaving a statement we have already diagnosed as wrong means every future
  # installation inherits it. The alternative, fixing only ScopeCopier, closes
  # the live path and knowingly ships the defect.
  def backfill
    workflows = WorkflowRule.table_name
    now = connection.quote(connection.quoted_date(Time.now.utc))

    { 'WorkflowTransition' => 'transitions', 'WorkflowPermission' => 'permissions' }.each do |sti_type, rule_type|
      say_with_time "Backfilling #{rule_type} scopes" do
        execute(<<~SQL.squish)
          INSERT INTO project_workflow_scopes
            (project_id, tracker_id, role_id, rule_type, created_at, updated_at)
          SELECT DISTINCT w.project_id, w.tracker_id, w.role_id,
                          #{connection.quote(rule_type)}, #{now}, #{now}
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
