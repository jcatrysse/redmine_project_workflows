# frozen_string_literal: true

# A place for a generic workflow write to wait (WP13, audit finding F07).
#
# One row per (rule_type, tracker, role), and the row means nothing beyond
# itself: it carries no rule, no project and no audit column, and nothing ever
# reads it for its contents. It exists so that `SELECT ... FOR UPDATE` has
# something to take for the generic population, which -- unlike a project --
# has no scope row to lock.
#
# Rows are created by Services::WriteCoordinator, the only thing that touches
# this table, and are never deleted: a combination that has been written once is
# one that can be written again, and the table is bounded by
# rule types x trackers x roles either way. The two foreign keys clear it up
# when a tracker or a role goes.
class ProjectWorkflowWriteLock < ActiveRecord::Base
  belongs_to :tracker
  belongs_to :role

  validates :tracker_id, :role_id, presence: true
  validates :rule_type, inclusion: { in: ProjectWorkflowScope::RULE_TYPES }
  validates :tracker_id, uniqueness: { scope: %i[role_id rule_type] }
end
