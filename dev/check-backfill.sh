#!/usr/bin/env bash
# The backfill of migration 004, end to end: seed the rules an installation from
# before ADR-001 would have, take the migration down and up again, and check that
# every (project, tracker, role) with rules -- and only those -- came back with a
# scope. Each step is its own process: a migration's effect is not visible
# through the schema cache of the process that ran it.
#
# Usage: dev/check-backfill.sh [target-dir] [ruby-version]
#
# Run it BEFORE the suite, for the same reason as the reversibility check:
# maintain_test_schema reloads db/schema.rb when the suite starts and wipes the
# plugin's migration bookkeeping, after which a VERSION= migration does nothing.
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-${REDMINE_DIR:-$PLUGIN_DIR/.redmine/5.1-stable-postgresql}}"
RUBY="${2:-${RUBY_VERSION:-}}"
if [ -n "$RUBY" ]; then
  export RBENV_VERSION="$RUBY"
  # See dev/setup.sh: rbenv on PATH does not imply its shims are on PATH.
  if [ -d /opt/rbenv/shims ]; then
    export PATH="/opt/rbenv/shims:$PATH"
  fi
fi
export RAILS_ENV=test
cd "$DIR"

# Fixed names rather than a per-run stamp, so that a run which died halfway
# leaves nothing behind for the next one to trip over: the first step removes
# whatever an earlier run may have left.
SRC=pwscope-source
DST=pwscope-target

bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null

bundle exec rails runner "
  # projects_trackers is in no spec's fixture list, so nothing truncates it, and
  # a run of this script that died between creating a project and destroying it
  # leaves rows behind for an id the projects sequence will hand out again --
  # after which Project.create! below dies on projects_trackers_unique and the
  # failure looks like a backfill defect. Sweep the orphans first.
  # No table alias: MariaDB 10.11 rejects one in a single-table DELETE, where
  # PostgreSQL and MySQL 8 accept it. NOT IN is safe here because projects.id
  # is never NULL.
  ActiveRecord::Base.connection.delete(
    'DELETE FROM projects_trackers WHERE project_id NOT IN (SELECT id FROM projects)'
  )
  Project.where(identifier: ['$SRC', '$DST']).each do |project|
    project.trackers.clear
    project.destroy
  end
  Tracker.where(name: 't-$SRC').each(&:destroy)
  Role.where(name: 'r-$SRC').each(&:destroy)
  IssueStatus.where(name: ['a-$SRC', 'b-$SRC']).each(&:destroy)

  a = IssueStatus.create!(name: 'a-$SRC')
  b = IssueStatus.create!(name: 'b-$SRC')
  t = Tracker.create!(name: 't-$SRC', default_status_id: a.id)
  r = Role.create!(name: 'r-$SRC')
  p = Project.create!(name: '$SRC', identifier: '$SRC')
  o = Project.create!(name: '$DST', identifier: '$DST')
  WorkflowTransition.create!(project_id: p.id, tracker_id: t.id, role_id: r.id, old_status_id: a.id, new_status_id: b.id)
  WorkflowTransition.create!(project_id: p.id, tracker_id: t.id, role_id: r.id, old_status_id: b.id, new_status_id: a.id)
  WorkflowPermission.create!(project_id: o.id, tracker_id: t.id, role_id: r.id, old_status_id: a.id, field_name: 'due_date', rule: 'required')
  WorkflowTransition.create!(project_id: nil, tracker_id: t.id, role_id: r.id, old_status_id: a.id, new_status_id: b.id)
  ProjectWorkflowScope.where(tracker_id: t.id).delete_all
"

bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=3 >/dev/null
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null

bundle exec rails runner "
  t = Tracker.find_by!(name: 't-$SRC')
  p = Project.find_by!(identifier: '$SRC')
  o = Project.find_by!(identifier: '$DST')
  begin
    scopes = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:project_id, :rule_type).sort
    expected = [[o.id, 'permissions'], [p.id, 'transitions']].sort
    raise \"backfill produced #{scopes.inspect}, expected #{expected.inspect}\" unless scopes == expected

    # This 600-second tolerance is real cover and it did NOT catch finding F09,
    # for a reason worth knowing: the backfill used CURRENT_TIMESTAMP, which is
    # UTC only on PostgreSQL, and every database *container* CI runs defaults to
    # UTC -- so the drift was zero on all nine cells and would only appear on a
    # MySQL or MariaDB server whose own timezone is not UTC, which no cell has.
    # The nine-cell matrix cannot find this class of defect; reading the adapter
    # source is what found it. The migration and ScopeCopier now build the value
    # in Ruby, so the question no longer arises.
    stamps = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:created_at, :updated_at).flatten
    raise 'backfill left a null timestamp' if stamps.any?(&:nil?)
    drift = stamps.map { |s| (Time.now.utc - s.utc).abs }.max
    raise \"backfill timestamps are #{drift.round}s off UTC\" if drift > 600

    puts \"backfill: #{scopes.inspect}\"
    puts 'two rules for one project gave one scope; the generic rule gave none; timestamps are UTC'
  ensure
    WorkflowRule.where(tracker_id: t.id).delete_all
    ProjectWorkflowScope.where(tracker_id: t.id).delete_all
    [p, o].each { |project| project.trackers.clear; project.destroy }
    t.destroy
    Role.find_by(name: 'r-$SRC')&.destroy
    IssueStatus.where(name: ['a-$SRC', 'b-$SRC']).each(&:destroy)
  end
  puts 'backfill check OK'
"
