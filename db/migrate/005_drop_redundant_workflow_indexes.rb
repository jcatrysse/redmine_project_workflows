# frozen_string_literal: true

# Two of the four indexes migrations 001 and 002 put on `workflows` can never be
# chosen over the other two, and every index is paid for on every insert -- and
# a workflow save inserts the whole matrix.
#
#   001  (project_id, role_id, tracker_id, old_status_id, type)          dropped
#   001  (project_id, tracker_id, role_id, type)                         dropped
#   002  (project_id, tracker_id, role_id, old_status_id, type)          kept
#   002  (project_id, tracker_id, role_id, old_status_id, field_name, type)  kept
#
# The first covers exactly the same columns as the third with role and tracker
# swapped; every query the plugin makes puts an equality predicate on both, and
# for equality the order of columns inside a composite index does not decide
# anything. The second is a strict prefix of the third, which a prefix lookup
# serves just as well. The two that remain are the two query shapes: transitions
# and field permissions (external F06, external F07).
#
# Reversible: down puts both back, so 001 and 002 can still take them away.
class DropRedundantWorkflowIndexes < ActiveRecord::Migration[6.1]
  REDUNDANT = [
    { columns: %i[project_id role_id tracker_id old_status_id type],
      name: 'index_workflows_on_project_role_tracker_old_status_type' },
    { columns: %i[project_id tracker_id role_id type],
      name: 'index_workflows_on_project_tracker_role_type' }
  ].freeze

  def up
    REDUNDANT.each do |index|
      next unless index_exists?(:workflows, index[:columns], name: index[:name])

      remove_index :workflows, name: index[:name]
    end
  end

  def down
    REDUNDANT.each do |index|
      next if index_exists?(:workflows, index[:columns], name: index[:name])

      add_index :workflows, index[:columns], name: index[:name]
    end
  end
end
