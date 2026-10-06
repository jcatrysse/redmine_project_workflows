# frozen_string_literal: true

class AddWorkflowsProjectForeignKey < ActiveRecord::Migration[6.1]
  def up
    return unless column_exists?(:workflows, :project_id)
    return if foreign_key_exists?(:workflows, :projects, column: :project_id)

    # `connection.delete` inside `say_with_time`, not `execute`, so the operator
    # sees the number (finding F20). `say_with_time` prints a row count only when
    # its block returns an Integer, and `execute` returns an adapter result
    # object -- so this printed the elapsed time and nothing else, on a DELETE
    # from Redmine's own central `workflows` table. On any installation upgrading
    # into this plugin the answer is **0 rows**: project rows cannot exist while
    # 001, 002 and 003 run, because 001 is what creates the column and all three
    # run in one rake invocation. Printing the zero is the point -- an unexplained
    # DELETE from a core table is exactly what an operator should be able to check.
    say_with_time 'Deleting workflow rows that name a project which no longer exists' do
      connection.delete(<<~SQL.squish)
        DELETE FROM workflows
        WHERE project_id IS NOT NULL
        AND project_id NOT IN (SELECT id FROM projects)
      SQL
    end

    # The one table rebuild in all five migrations, and only on MySQL and
    # MariaDB: MySQL's online-DDL notes are explicit that INPLACE for adding a
    # foreign key is supported only when foreign_key_checks is disabled, and
    # Rails' add_foreign_key does not disable it -- so this is a COPY-algorithm
    # rebuild there. `workflows` is an O(configuration) table rather than an
    # O(data) one: it does not grow with issues, journals or time. Measured on a
    # synthetic 900,000-row / 80 MB table -- ten to fifty times larger than
    # realistic -- the whole of this plugin's DDL is about 7.4 seconds, of which
    # this statement is 77 ms on PostgreSQL. See docs/design.md and README.md.
    add_foreign_key :workflows, :projects, column: :project_id, on_delete: :cascade
  end

  def down
    return unless foreign_key_exists?(:workflows, :projects, column: :project_id)

    remove_foreign_key :workflows, column: :project_id
  end
end
