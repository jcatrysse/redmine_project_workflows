#!/usr/bin/env bash
# WP16 -- the backup-aware uninstall, rehearsed end to end against a real
# database.
#
# dev/check-upgrade.sh establishes what a downgrade costs: `VERSION=0` deletes
# every workflow rule that names a project and drops the table recording which
# projects decided to have one, so it discards every project workflow and keeps
# the generic one. That is deliberate -- dropping the column with those rows
# still in the table would turn every project's rules into rules of the workflow
# every project shares -- and it is exactly why the plugin now ships a backup.
#
# This script is the other half: it runs the uninstall an administrator runs,
# through the plugin's own rake tasks, over the shapes that are easy to lose.
#
#   1. an ordinary own workflow -- transitions and field permissions;
#   2. an own **empty** decision, which the scope row is the only record of;
#   3. an audit trail, so that a restore does not attribute every project's
#      workflow to whoever ran it;
#   4. the generic workflow, which must be untouched throughout.
#
# Four legs:
#
#   * the refusal -- `uninstall` without CONFIRM=yes changes nothing and writes
#     no file, so a forgotten flag does not leave a half-finished backup behind;
#   * the uninstall -- backup, then every migration reversed, then the host
#     checked to be stock;
#   * the reinstall -- migrate up, restore, and every one of the four shapes
#     compared with what was there before;
#   * the second restore -- run again over the database it just restored, which
#     must change nothing, because an operator who is not sure whether it worked
#     will run it twice.
#
# Usage: dev/check-uninstall.sh [target-dir] [ruby-version]
#
# Run it BEFORE the suite, for the reason the other migration checks give:
# maintain_test_schema reloads db/schema.rb when the suite starts and wipes the
# plugin's migration bookkeeping, after which a VERSION= migration silently does
# nothing.
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BACKUP="$WORK/project-workflows.json"

# Fixed names rather than a per-run stamp, so a run that died halfway leaves
# nothing for the next one to trip over.
P=pwuninstall-project
Q=pwuninstall-empty

bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null

echo '==> seeding an own workflow, an own EMPTY decision, an audit trail and a generic rule'
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
  User.where(login: 'u-$P').each(&:destroy)

  a = IssueStatus.create!(name: 'a-$P')
  b = IssueStatus.create!(name: 'b-$P')
  t = Tracker.create!(name: 't-$P', default_status_id: a.id)
  r = Role.create!(name: 'r-$P')
  p = Project.create!(name: '$P', identifier: '$P')
  q = Project.create!(name: '$Q', identifier: '$Q')
  editor = User.create!(login: 'u-$P', firstname: 'Un', lastname: 'Install',
                        mail: 'u-$P@example.com')

  # the generic workflow, which nothing here may touch
  WorkflowTransition.create!(project_id: nil, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id)

  # 1. an ordinary own workflow: one cell as two rows, and a field permission
  ProjectWorkflowScope.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                               rule_type: 'transitions', created_by_id: editor.id)
  WorkflowTransition.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id)
  WorkflowTransition.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id,
                             author: true, assignee: true)
  ProjectWorkflowScope.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                               rule_type: 'permissions', created_by_id: editor.id)
  WorkflowPermission.create!(project_id: p.id, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, field_name: 'due_date', rule: 'required')

  # 2. an own EMPTY decision: a scope with no rule under it at all
  ProjectWorkflowScope.create!(project_id: q.id, tracker_id: t.id, role_id: r.id,
                               rule_type: 'transitions', created_by_id: editor.id)
  puts 'seeded'
"

echo '==> leg 1, the refusal: no CONFIRM=yes changes nothing and writes no file'
# The output is checked, not only the exit status. A task that does not exist,
# or a host the working tree was never synced into, also exits non-zero -- and
# the first version of this leg passed on exactly that.
if bundle exec rake redmine_project_workflows:uninstall FILE="$BACKUP" >"$WORK/refusal.log" 2>&1; then
  echo 'uninstall ran without CONFIRM=yes' >&2
  exit 1
fi
if ! grep -q 'refusing to reverse the migrations without CONFIRM=yes' "$WORK/refusal.log"; then
  echo 'the uninstall failed for some reason other than the missing confirmation:' >&2
  cat "$WORK/refusal.log" >&2
  exit 1
fi
# ...and it said what was at stake before it refused.
grep -q 'delete every workflow rule that names a project' "$WORK/refusal.log"
if [ -e "$BACKUP" ]; then
  echo 'a refused uninstall left a backup file behind' >&2
  exit 1
fi
bundle exec rails runner "
  raise 'the refused uninstall dropped the scope table' unless
    ActiveRecord::Base.connection.tables.include?('project_workflow_scopes')
  puts 'refused, and nothing changed'
"

echo '==> leg 2, the uninstall: backup, then every migration reversed'
bundle exec rake redmine_project_workflows:uninstall FILE="$BACKUP" CONFIRM=yes

bundle exec rails runner "
  connection = ActiveRecord::Base.connection
  leftovers = connection.tables.grep(/project_workflow/)
  raise \"the uninstall left tables behind: #{leftovers.inspect}\" if leftovers.any?
  raise 'the uninstall left project_id on workflows' if connection.columns('workflows').map(&:name).include?('project_id')

  t = Tracker.find_by!(name: 't-$P')
  rules = WorkflowRule.where(tracker_id: t.id).count
  raise \"the uninstall left #{rules} rules, expected the 1 generic one\" unless rules == 1
  puts 'stock again: the generic workflow intact, every project workflow discarded'
"

# Read with plain ruby rather than through the application: at this point the
# plugin's tables are gone, and the one thing that still has to be true is that
# the file written before they went is readable on its own.
ruby -rjson -e '
  document = JSON.parse(File.read(ARGV[0]))
  raise "not a backup: #{document["format"].inspect}" unless
    document["format"] == "redmine_project_workflows.backup"
  raise "the backup recorded #{document["scopes"].size} decisions" unless document["scopes"].size >= 3
  raise "the backup recorded #{document["rules"].size} rules" unless document["rules"].size >= 3
  puts "the backup holds #{document["scopes"].size} decisions and #{document["rules"].size} rules"
' "$BACKUP"

echo '==> leg 3, the reinstall: migrate up and restore'
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null
bundle exec rake redmine_project_workflows:restore FILE="$BACKUP"

bundle exec rails runner "
  t = Tracker.find_by!(name: 't-$P')
  p = Project.find_by!(identifier: '$P')
  q = Project.find_by!(identifier: '$Q')
  editor = User.find_by!(login: 'u-$P')

  scopes = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:project_id, :rule_type).sort
  expected = [[p.id, 'permissions'], [p.id, 'transitions'], [q.id, 'transitions']].sort
  raise \"the restore produced #{scopes.inspect}, expected #{expected.inspect}\" unless scopes == expected

  # 1. the own workflow, one cell as two rows again
  flags = WorkflowTransition.where(project_id: p.id, tracker_id: t.id)
                            .pluck(:author, :assignee).sort_by(&:to_s)
  raise \"the transitions came back as #{flags.inspect}\" unless flags == [[false, false], [true, true]]
  permissions = WorkflowPermission.where(project_id: p.id, tracker_id: t.id)
                                  .pluck(:field_name, :rule)
  raise \"the field permissions came back as #{permissions.inspect}\" unless
    permissions == [['due_date', 'required']]

  # 2. the own EMPTY decision: the scope is back and still has no rules
  raise 'the own empty workflow came back with rules in it' if
    WorkflowRule.where(project_id: q.id).exists?

  # 3. the audit trail, not the operator who ran the restore
  authors = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:created_by_id).uniq
  raise \"the restore reattributed the decisions: #{authors.inspect}\" unless authors == [editor.id]

  # 4. the generic workflow, untouched throughout
  generic = WorkflowTransition.where(project_id: nil, tracker_id: t.id).count
  raise \"the generic workflow is #{generic} rules, expected 1\" unless generic == 1
  puts 'restored: rules, the empty decision, the audit trail, and the generic workflow untouched'
"

echo '==> leg 4, the second restore: running it again changes nothing'
bundle exec rake redmine_project_workflows:restore FILE="$BACKUP"

bundle exec rails runner "
  t = Tracker.find_by!(name: 't-$P')
  p = Project.find_by!(identifier: '$P')
  q = Project.find_by!(identifier: '$Q')
  begin
    scopes = ProjectWorkflowScope.where(tracker_id: t.id).count
    raise \"a second restore left #{scopes} decisions, expected 3\" unless scopes == 3
    rules = WorkflowRule.where(tracker_id: t.id).count
    # One generic, two transition rows for the one cell, one field permission.
    raise \"a second restore left #{rules} rules, expected 4\" unless rules == 4
    puts 'a second restore changed nothing'
  ensure
    WorkflowRule.where(tracker_id: t.id).delete_all
    ProjectWorkflowScope.where(tracker_id: t.id).delete_all
    [p, q].each { |x| x.trackers.clear; x.destroy }
    t.destroy
    Role.find_by(name: 'r-$P')&.destroy
    IssueStatus.where(name: ['a-$P', 'b-$P']).each(&:destroy)
    User.find_by(login: 'u-$P')&.destroy
  end
  puts 'uninstall rehearsal OK'
"
