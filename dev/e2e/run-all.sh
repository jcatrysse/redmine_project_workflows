#!/usr/bin/env bash
# Every scenario, in order, from a known state.
set -u
HOST="${1:-/home/user/redmine_project_workflows/.redmine/5.1-stable-postgresql}"
RUBY="${2:-3.2.6}"
here="$(cd "$(dirname "$0")" && pwd)"

reset() {
  (cd "$HOST" && RAILS_ENV=development RBENV_VERSION="$RUBY" PATH="/opt/rbenv/shims:$PATH" \
    bundle exec rails runner '
      ProjectWorkflowScope.delete_all
      WorkflowRule.where.not(project_id: nil).delete_all
      Issue.delete_all
    ' >/dev/null 2>&1)
}

fail=0
for s in admin manager effect guard screens; do
  echo "=============================== $s"
  reset
  if [ "$s" = "screens" ]; then
    (cd "$HOST" && RAILS_ENV=development RBENV_VERSION="$RUBY" PATH="/opt/rbenv/shims:$PATH" \
      bundle exec rails runner '
        User.current = User.find(1)
        a = Project.find_by(identifier: "alpha"); m = Role.find_by(name: "Manager"); t = Tracker.find_by(name: "Bug")
        RedmineProjectWorkflows::Services::ScopeWriter.enable(project_ids: [a.id], tracker_ids: [t.id],
          role_ids: [m.id], rule_type: "transitions", copy_generic: true, user: User.find(1))
        WorkflowTransition.where(project_id: a.id, tracker_id: t.id, role_id: m.id).limit(3).destroy_all
      ' >/dev/null 2>&1)
  fi
  (cd "$here" && node "$s.mjs") || fail=1
done
reset
echo "==============================="
[ $fail -eq 0 ] && echo "ALL SCENARIOS PASSED" || echo "SOME SCENARIOS FAILED"
exit $fail
