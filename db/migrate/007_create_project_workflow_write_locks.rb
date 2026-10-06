# frozen_string_literal: true

# The generic workflow's missing lock row (WP13, audit finding F07).
#
# A project write locks the scope rows of the combinations it is about to
# rewrite, so "does this project run its own workflow here?" and "write its
# rules" are one decision. A **generic** write has no scope row -- the generic
# workflow is what a project inherits, not something a project decides -- so it
# locked nothing at all, and two administrators saving the same matrix at the
# same moment could both find no row to delete and both insert one. Core has the
# identical race and carries an opportunistic duplicate-repair line to prove it
# knows; the plugin is the write path for both populations and can hold one
# policy instead of two.
#
# So: one row per (rule_type, tracker, role) whose only purpose is to be locked.
# It carries no workflow data and is never read for its contents. A row is
# created the first time a generic write names its combination and then lives
# for the life of the installation, which is why the table is at most
# rule types x trackers x roles rows.
#
# A plugin-owned table rather than an advisory lock: PostgreSQL, MySQL and
# MariaDB have no advisory-lock call in common, and SELECT ... FOR UPDATE is the
# one thing all three speak -- it is already what the scope rows are locked with.
class CreateProjectWorkflowWriteLocks < ActiveRecord::Migration[6.1]
  # :integer rather than the Rails default :bigint, for the reason migration 004
  # gives: Redmine's own primary keys are 4-byte integers and MySQL refuses a
  # foreign key whose column width differs from the one it references.
  def up
    # No timestamps, and the cop is disabled rather than satisfied: the row
    # records no event. A created_at would be the first time anybody saved that
    # combination, which is not a fact the plugin uses or shows anywhere, and an
    # updated_at would never change -- two columns that would read as an audit
    # trail beside the one in project_workflow_scopes, which is a real one.
    create_table :project_workflow_write_locks do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.string :rule_type, null: false, limit: 20
      t.integer :tracker_id, null: false
      t.integer :role_id, null: false
    end

    # Unique because the row *is* the key: two rows for one combination would be
    # two locks for one workflow, which is no lock at all. It is also what makes
    # the create-then-lock sequence safe -- a concurrent create blocks on the
    # index and then loses with RecordNotUnique rather than adding a second row.
    add_index :project_workflow_write_locks,
              %i[rule_type tracker_id role_id],
              unique: true,
              name: 'index_project_workflow_write_locks_unique'

    add_foreign_key :project_workflow_write_locks, :trackers, column: :tracker_id, on_delete: :cascade
    add_foreign_key :project_workflow_write_locks, :roles, column: :role_id, on_delete: :cascade
  end

  # INV-8: VERSION=0 leaves nothing behind. There is nothing to preserve here --
  # the rows carry no decision, only a place to wait.
  def down
    drop_table :project_workflow_write_locks
  end
end
