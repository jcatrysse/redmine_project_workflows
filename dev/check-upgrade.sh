#!/usr/bin/env bash
# WP15 item 5 -- an upgrade rehearsal, with the data an installation actually
# has in it.
#
# dev/check-backfill.sh already takes migration 004 down and up again over a
# project that has rules, which is the backfill's own happy path. What it does
# not do is rehearse the *whole* migration set the way an upgrade runs it, over
# the four shapes of data three reviews named:
#
#   1. project rules under a scope -- an ordinary own workflow;
#   2. an own **empty** scope -- a decision with no rules under it, which is the
#      state INV-3 exists to keep distinguishable from inheritance;
#   3. duplicate rules -- two identical rows, which a pre-0.1.6 database can
#      carry because the write lock did not exist yet;
#   4. an orphaned audit user -- a scope whose `created_by_id` names a user who
#      has since been deleted.
#
# It has two legs, because they answer different questions.
#
#   * **The upgrade**, which is what a release does: down to VERSION=3 -- before
#     the scope table, which is where an installation on 0.0.3 stands -- and up
#     again over data that is already there. Every migration this plugin has
#     shipped runs in order, and the backfill has to reconstruct the decisions
#     from the rules it finds.
#   * **The downgrade**, VERSION=0, which INV-8 promises returns the host to
#     stock. It is not the reverse of the upgrade and must not be read as one:
#     migration 001's `down` deletes every rule that names a project, on purpose
#     -- without it, dropping the column would turn every project's rules into
#     rules of the workflow every project shares, which is the worst possible
#     silent widening. So a downgrade discards every project workflow and keeps
#     the generic one. That is the sentence WP16's downgrade procedure has to
#     open with, and this script is where it is checked rather than believed.
#
# Usage: dev/check-upgrade.sh [target-dir] [ruby-version]
#
# Run it BEFORE the suite, for the same reason as the other two migration
# checks: maintain_test_schema reloads db/schema.rb when the suite starts and
# wipes the plugin's migration bookkeeping, after which a VERSION= migration
# silently does nothing.
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

# Fixed names rather than a per-run stamp, so a run that died halfway leaves
# nothing for the next one to trip over: the seeding step removes whatever an
# earlier run may have left.
P=pwupgrade-project
Q=pwupgrade-empty

bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null

echo '==> seeding the four shapes'
bundle exec rails runner "
  # See dev/check-backfill.sh: projects_trackers is in no fixture list, so a run
  # that died between creating a project and destroying it leaves rows behind
  # for an id the sequence will hand out again.
  ActiveRecord::Base.connection.delete(
    'DELETE FROM projects_trackers WHERE project_id NOT IN (SELECT id FROM projects)'
  )
  Project.where(identifier: ['$P', '$Q']).each { |x| x.trackers.clear; x.destroy }
  Tracker.where(name: 't-$P').each(&:destroy)
  Role.where(name: 'r-$P').each(&:destroy)
  IssueStatus.where(name: ['a-$P', 'b-$P']).each(&:destroy)
  User.where(login: 'u-$P').each { |u| u.destroy }

  a = IssueStatus.create!(name: 'a-$P')
  b = IssueStatus.create!(name: 'b-$P')
  t = Tracker.create!(name: 't-$P', default_status_id: a.id)
  r = Role.create!(name: 'r-$P')
  p = Project.create!(name: '$P', identifier: '$P')
  q = Project.create!(name: '$Q', identifier: '$Q')

  editor = User.new(login: 'u-$P', firstname: 'Up', lastname: 'Grade', mail: 'u-$P@example.com')
  editor.save!

  # 1. an ordinary own workflow, and the generic rule it replaces
  WorkflowTransition.create!(project_id: nil, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id)
  WorkflowTransition.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id)
  # 3. a duplicate of it, which is what a pre-0.1.6 race left behind
  WorkflowTransition.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id)

  # 2. an own EMPTY decision: a scope with no rule under it at all
  ProjectWorkflowScope.create!(project_id: q.id, tracker_id: t.id, role_id: r.id,
                               rule_type: 'transitions')
  # 4. ...whose author is then deleted, leaving the audit column dangling
  stamped = ProjectWorkflowScope.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                                         rule_type: 'permissions', created_by_id: editor.id)
  WorkflowPermission.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, field_name: 'due_date', rule: 'required')
  editor.destroy
  raise 'the audit column did not survive the author being deleted' unless
    ProjectWorkflowScope.find(stamped.id).created_by_id.nil?
  puts 'seeded: own workflow + duplicate, own empty, orphaned audit user'
"

echo '==> leg 1, the upgrade: down to VERSION=3, where an installation on 0.0.3 stands'
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=3 >/dev/null

bundle exec rails runner "
  connection = ActiveRecord::Base.connection
  raise 'the scope table survived VERSION=3' if connection.tables.include?('project_workflow_scopes')
  raise 'project_id went with it' unless connection.columns('workflows').map(&:name).include?('project_id')
  t = Tracker.find_by!(name: 't-$P')
  rules = WorkflowRule.where(tracker_id: t.id).count
  raise \"VERSION=3 changed the rule count to #{rules}, expected 4\" unless rules == 4
  puts 'at VERSION=3: no decisions recorded anywhere, four rules intact'
"

echo '==> and up again, the way an upgrade from 0.0.3 runs'
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null

bundle exec rails runner "
  t = Tracker.find_by!(name: 't-$P')
  p = Project.find_by!(identifier: '$P')
  q = Project.find_by!(identifier: '$Q')
  scopes = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:project_id, :rule_type).sort
  # Both of the project's populations come back, because both have rules. The
  # empty project's does not: a scope was the only record that such a decision
  # was ever made, and before 004 there was no table to hold it. An installation
  # upgrading from 0.0.3 therefore has no own-EMPTY workflows, which is right --
  # it could not have had one.
  expected = [[p.id, 'permissions'], [p.id, 'transitions']].sort
  raise \"the backfill produced #{scopes.inspect}, expected #{expected.inspect}\" unless scopes == expected
  raise 'an own EMPTY decision appeared out of nothing' if ProjectWorkflowScope.exists?(project_id: q.id)

  # The rules survived untouched, duplicate and all: a migration is not the place
  # to repair data -- the README's repair task is, and it is a separate decision
  # an administrator makes.
  rules = WorkflowRule.where(tracker_id: t.id).count
  raise \"the upgrade changed the rule count to #{rules}, expected 4\" unless rules == 4
  duplicates = WorkflowTransition.where(project_id: p.id, tracker_id: t.id).count
  raise \"the duplicate pair became #{duplicates} rows\" unless duplicates == 2

  # Every backfilled scope is unattributed, because there is nothing to attribute
  # it to -- and the column has to be nullable for that to be possible at all.
  authors = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:created_by_id).uniq
  raise \"the backfill invented an author: #{authors.inspect}\" unless authors == [nil]

  puts \"upgrade: #{scopes.inspect}\"
  puts 'rules and their duplicate survived; the backfill attributed nothing to anybody'
"

echo '==> leg 2, the downgrade: VERSION=0, which INV-8 promises returns the host to stock'
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0 >/dev/null

bundle exec rails runner "
  connection = ActiveRecord::Base.connection
  leftovers = connection.tables.grep(/project_workflow/)
  raise \"VERSION=0 left tables behind: #{leftovers.inspect}\" if leftovers.any?
  raise 'VERSION=0 left project_id on workflows' if connection.columns('workflows').map(&:name).include?('project_id')

  t = Tracker.find_by!(name: 't-$P')
  rules = WorkflowRule.where(tracker_id: t.id).count
  # One: the generic rule. The four that named a project are gone, deliberately
  # -- see the header. Nothing else in this repository says this out loud.
  raise \"a downgrade left #{rules} rules, expected the 1 generic one\" unless rules == 1
  puts 'stock again: the generic workflow intact, every project workflow discarded'
"

echo '==> and up once more, so the host is left as this script found it'
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null

bundle exec rails runner "
  t = Tracker.find_by!(name: 't-$P')
  p = Project.find_by!(identifier: '$P')
  q = Project.find_by!(identifier: '$Q')
  begin
    raise 'a decision came back from a downgrade' if ProjectWorkflowScope.exists?(tracker_id: t.id)
    raise 'the generic rule did not survive' unless WorkflowRule.where(tracker_id: t.id).count == 1
  ensure
    WorkflowRule.where(tracker_id: t.id).delete_all
    ProjectWorkflowScope.where(tracker_id: t.id).delete_all
    [p, q].each { |x| x.trackers.clear; x.destroy }
    t.destroy
    Role.find_by(name: 'r-$P')&.destroy
    IssueStatus.where(name: ['a-$P', 'b-$P']).each(&:destroy)
  end
  puts 'upgrade rehearsal OK'
"
