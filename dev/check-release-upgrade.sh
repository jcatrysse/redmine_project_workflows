#!/usr/bin/env bash
# WP16 item 1 -- the upgrade rehearsal that starts from a checkout of the
# previous release, running that release's own code.
#
# dev/check-upgrade.sh already rehearses the migration *path*: down to
# VERSION=3, where an installation on 0.0.3 stands, and up again over populated
# data. What it cannot do is run the previous release's **code**, and two
# questions need that:
#
#   1. Were the rows an installation actually holds written by the same writers
#      the new code assumes wrote them? A migration rehearsal seeds its data with
#      today's models, which is the one thing a real upgrade never does.
#   2. Does the installation still *behave* the same afterwards? 0.0.3 had no
#      scope table: "this project has rules, therefore it overrides" was the
#      whole model, and migration 004's backfill has to reconstruct exactly that
#      decision for every combination. The only honest test of "exactly" is to
#      ask the old code what an issue may do, upgrade, and ask the new code the
#      same question.
#
# So this script installs the plugin at REF into the host, writes project rules
# through **that release's** writers, records what it answers, swaps the working
# tree in, migrates, and compares.
#
# REF defaults to origin/main, which is what the last release is: this
# repository has no tags, and a branch that no session writes to is a stable
# enough ref for a rehearsal. Pass any ref -- a tag, once one exists.
#
# Usage: dev/check-release-upgrade.sh [ref] [target-dir] [ruby-version]
#
# **It rebuilds the host's test database from core migrations**, because it has
# to start from one that has never seen migrations 004-007, and it leaves the
# host holding the working tree and every migration applied. It is the only
# check here that rebuilds rather than requiring a rebuild.
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:-${RELEASE_REF:-origin/main}}"
DIR="${2:-${REDMINE_DIR:-$PLUGIN_DIR/.redmine/5.1-stable-postgresql}}"
RUBY="${3:-${RUBY_VERSION:-}}"
if [ -n "$RUBY" ]; then
  export RBENV_VERSION="$RUBY"
  # See dev/setup.sh: rbenv on PATH does not imply its shims are on PATH.
  if [ -d /opt/rbenv/shims ]; then
    export PATH="/opt/rbenv/shims:$PATH"
  fi
fi
export RAILS_ENV=test
case "$DIR" in /*) ;; *) DIR="$PLUGIN_DIR/$DIR" ;; esac
HOST_PLUGIN="$DIR/plugins/$(basename "$PLUGIN_DIR")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BEFORE="$WORK/before.json"

git -C "$PLUGIN_DIR" rev-parse --verify --quiet "$REF^{commit}" >/dev/null || {
  echo "no such ref: $REF" >&2
  exit 1
}
RELEASED_VERSION="$(git -C "$PLUGIN_DIR" show "$REF:init.rb" | sed -n "s/^ *version '\\(.*\\)'/\\1/p")"
WORKING_VERSION="$(sed -n "s/^ *version '\\(.*\\)'/\\1/p" "$PLUGIN_DIR/init.rb")"
echo "==> rehearsing an upgrade from $REF (version ${RELEASED_VERSION:-unknown}) to the working tree (version $WORKING_VERSION)"

# Fixed names rather than a per-run stamp, so a run that died halfway leaves
# nothing for the next one to trip over.
P=pwrelease-owns
Q=pwrelease-inherits

echo '==> a stock database: this rehearsal has to start where 0.0.3 stood'
( cd "$DIR" && rm -f db/schema.rb && bundle exec rake db:drop db:create db:migrate >/dev/null )

echo "==> installing the plugin as it is at $REF"
rm -rf "$HOST_PLUGIN"
mkdir -p "$HOST_PLUGIN"
git -C "$PLUGIN_DIR" archive "$REF" | tar -x -C "$HOST_PLUGIN"
# Redmine evals every plugin's Gemfile into its own, and the released one is not
# the working tree's.
( cd "$DIR" && bundle install >/dev/null )
( cd "$DIR" && bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null )

( cd "$DIR" && bundle exec rails runner "
  connection = ActiveRecord::Base.connection
  raise 'the released plugin created the scope table' if connection.tables.include?('project_workflow_scopes')
  raise 'the released plugin did not add project_id' unless
    connection.columns('workflows').map(&:name).include?('project_id')
  puts 'at the released version: project_id on workflows, and no scope table'
" )

echo '==> seeding through the RELEASED plugin: its writers, not the ones in the working tree'
( cd "$DIR" && bundle exec rails runner "
  # See dev/check-backfill.sh: projects_trackers is in no fixture list, so a run
  # that died between creating a project and destroying it leaves rows behind
  # for an id the sequence will hand out again.
  ActiveRecord::Base.connection.delete(
    'DELETE FROM projects_trackers WHERE project_id NOT IN (SELECT id FROM projects)'
  )
  Project.where(identifier: ['$P', '$Q']).each { |x| x.trackers.clear; x.destroy }
  Tracker.where(name: 't-$P').each(&:destroy)
  Role.where(name: 'r-$P').each(&:destroy)
  IssueStatus.where(name: ['a-$P', 'b-$P', 'c-$P']).each(&:destroy)
  User.where(login: 'u-$P').each(&:destroy)

  a = IssueStatus.create!(name: 'a-$P')
  b = IssueStatus.create!(name: 'b-$P')
  c = IssueStatus.create!(name: 'c-$P')
  t = Tracker.create!(name: 't-$P', default_status_id: a.id)
  # add_issues/edit_issues, not merely 'not builtin': Issue#roles_for_workflow
  # keeps only roles answering consider_workflow?, and a role without them is
  # filtered out by core before the plugin ever sees it.
  r = Role.create!(name: 'r-$P', permissions: [:view_issues, :add_issues, :edit_issues])
  owns = Project.create!(name: '$P', identifier: '$P')
  inherits = Project.create!(name: '$Q', identifier: '$Q')
  [owns, inherits].each { |x| x.trackers = [t]; x.save! }
  user = User.create!(login: 'u-$P', firstname: 'Up', lastname: 'Grade', mail: 'u-$P@example.com')
  [owns, inherits].each do |x|
    Member.create!(project: x, principal: user, roles: [r])
  end

  # The workflow every project shares: a -> b.
  WorkflowTransition.create!(project_id: nil, tracker_id: t.id, role_id: r.id,
                             old_status_id: a.id, new_status_id: b.id)

  # ...and one project of its own, written by the RELEASED writers, which is the
  # whole point of this leg: these are the rows a real installation has in it.
  RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions(
    owns, [t], [r], { a.id.to_s => { c.id.to_s => { 'always' => '1' } } }
  )
  RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions(
    owns, [t], [r], { a.id.to_s => { 'due_date' => 'required' } }
  )

  # One saved issue per project, sitting on status a. A *new* issue transitions
  # out of the *new issue* pseudo status (old_status_id 0), which is not what
  # this workflow is about -- ask an unsaved one and every answer below is the
  # default status and nothing else, which is a comparison of nothing against
  # nothing.
  [owns, inherits].each do |project|
    # due_date is set because the field permission written a moment ago makes it
    # required in the overriding project -- which is the plugin doing its job,
    # and is the first thing this rehearsal proved about the released code.
    Issue.create!(project: project, tracker: t, status: a, subject: 'i-' + project.identifier,
                  author: user, due_date: Date.today,
                  priority: IssuePriority.first || IssuePriority.create!(name: 'p-$P'))
  end

  # The premise of the whole rehearsal, checked rather than assumed: the released
  # writers actually put project rows in the table. The first version of this
  # script lost them to a shell quoting mistake and went on to report that the
  # backfill produced nothing -- which was true, and about the wrong thing.
  written = WorkflowRule.where(tracker_id: t.id).where.not(project_id: nil).count
  raise 'the released writers wrote ' + written.to_s + ' project rules, expected 2' unless written == 2
  puts 'seeded through the released writers: 1 generic rule, 2 project rules, 2 issues'
" )

echo '==> and asking the RELEASED plugin what an issue may do'
( cd "$DIR" && bundle exec rails runner "
  require 'json'
  t = Tracker.find_by!(name: 't-$P')
  a = IssueStatus.find_by!(name: 'a-$P')
  user = User.find_by!(login: 'u-$P')
  answer = {}
  ['$P', '$Q'].each do |identifier|
    project = Project.find_by!(identifier: identifier)
    issue = Issue.find_by!(project_id: project.id, tracker_id: t.id)
    answer[identifier] = {
      'statuses' => issue.new_statuses_allowed_to(user).map(&:name).sort,
      'required' => issue.required_attribute_names(user).sort
    }
  end
  answer['rules'] = WorkflowRule.where(tracker_id: t.id)
                                .order(:project_id, :role_id, :type, :old_status_id, :new_status_id, :field_name)
                                .pluck(:type, :project_id, :role_id, :old_status_id, :new_status_id,
                                       :field_name, :rule, :author, :assignee)
  answer['role_permissions'] = Role.find_by!(name: 'r-$P').permissions.map(&:to_s).sort
  raise 'the two projects answer the same thing, so this rehearsal compares nothing' if
    answer['$P']['statuses'] == answer['$Q']['statuses']
  File.write('$BEFORE', JSON.pretty_generate(answer))
  puts \"released version answers: #{answer['$P']['statuses'].inspect} in the overriding project, \" \
       \"#{answer['$Q']['statuses'].inspect} in the inheriting one\"
" )

echo '==> upgrading: the working tree in, and every migration the release did not have'
rsync -a --delete --exclude '.git/' --exclude '.redmine/' --exclude 'vendor/' \
  "$PLUGIN_DIR/" "$HOST_PLUGIN/"
( cd "$DIR" && bundle install >/dev/null )
( cd "$DIR" && bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows )

echo '==> and asking the UPGRADED plugin the same questions'
( cd "$DIR" && bundle exec rails runner "
  require 'json'
  before = JSON.parse(File.read('$BEFORE'))
  t = Tracker.find_by!(name: 't-$P')
  a = IssueStatus.find_by!(name: 'a-$P')
  user = User.find_by!(login: 'u-$P')
  owns = Project.find_by!(identifier: '$P')
  inherits = Project.find_by!(identifier: '$Q')
  failures = []
  begin
    ['$P', '$Q'].each do |identifier|
      project = Project.find_by!(identifier: identifier)
      issue = Issue.find_by!(project_id: project.id, tracker_id: t.id)
      statuses = issue.new_statuses_allowed_to(user).map(&:name).sort
      required = issue.required_attribute_names(user).sort
      failures << \"#{identifier}: statuses were #{before[identifier]['statuses'].inspect}, \" \
                  \"are #{statuses.inspect}\" unless statuses == before[identifier]['statuses']
      failures << \"#{identifier}: required fields were #{before[identifier]['required'].inspect}, \" \
                  \"are #{required.inspect}\" unless required == before[identifier]['required']
    end

    # Not one rule added, removed or changed. The upgrade records decisions; it
    # does not touch the rules those decisions are about -- duplicates included,
    # which is a repair an administrator asks for separately.
    rules = WorkflowRule.where(tracker_id: t.id)
                        .order(:project_id, :role_id, :type, :old_status_id, :new_status_id, :field_name)
                        .pluck(:type, :project_id, :role_id, :old_status_id, :new_status_id,
                               :field_name, :rule, :author, :assignee)
    failures << \"the rules changed: #{before['rules'].inspect} -> #{rules.inspect}\" unless
      rules.map(&:to_json) == before['rules'].map(&:to_json)

    # The backfill reconstructed the implicit model exactly: a decision for every
    # combination that has rules, and for no other.
    scopes = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:project_id, :rule_type).sort
    expected = [[owns.id, 'permissions'], [owns.id, 'transitions']].sort
    failures << \"the backfill produced #{scopes.inspect}, expected #{expected.inspect}\" unless scopes == expected
    failures << 'the inheriting project was given a workflow of its own' if
      ProjectWorkflowScope.exists?(project_id: inherits.id)
    authors = ProjectWorkflowScope.where(tracker_id: t.id).pluck(:created_by_id).uniq
    failures << \"the backfill invented an author: #{authors.inspect}\" unless authors == [nil]

    # The released version registered no permissions at all, so migration 006 --
    # which renames this plugin's two permissions inside roles.permissions -- has
    # nothing to rename here, and must not invent anything.
    permissions = Role.find_by!(name: 'r-$P').permissions.map(&:to_s).sort
    failures << \"the permission rename changed a role: #{before['role_permissions'].inspect} -> \" \
                \"#{permissions.inspect}\" unless permissions == before['role_permissions']

    raise \"upgrade from the released version changed behaviour:\n  #{failures.join(\"\n  \")}\" if failures.any?
    puts 'behaviour unchanged, rules untouched, the backfill reproduced the implicit model'
  ensure
    Issue.where(tracker_id: t.id).destroy_all
    WorkflowRule.where(tracker_id: t.id).delete_all
    ProjectWorkflowScope.where(tracker_id: t.id).delete_all
    [owns, inherits].each { |x| x.trackers.clear; x.destroy }
    t.destroy
    Role.find_by(name: 'r-$P')&.destroy
    IssueStatus.where(name: ['a-$P', 'b-$P', 'c-$P']).each(&:destroy)
    User.find_by(login: 'u-$P')&.destroy
  end
  puts 'release upgrade rehearsal OK'
" )
