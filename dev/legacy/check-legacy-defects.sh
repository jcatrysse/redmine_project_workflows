#!/usr/bin/env bash
# Reproduces, against 0.0.3 itself, the five defects session B2 of the Jira
# migration read in that release (docs/review/findings/2026-10-14-claude-migration-test.md).
#
#   dev/legacy/check-legacy-defects.sh [redmine-host-dir] [ruby-version]
#
# Rebuilds the host's TEST database from core migrations, installs the plugin as
# it is at origin/main (0.0.3), prints one line per defect, and then puts the
# working tree and a fresh database back. Expect five "DEFECT REPRODUCED" lines.
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${1:-$PLUGIN_DIR/.redmine/51geo-postgresql}"; RUBY="${2:-3.2.6}"
HOST_PLUGIN=$DIR/plugins/redmine_project_workflows
export RBENV_VERSION=$RUBY PATH="/opt/rbenv/shims:$PATH" RAILS_ENV=test
cd "$DIR"
rm -f db/schema.rb && bundle exec rake db:drop db:create db:migrate >/dev/null
rm -rf "$HOST_PLUGIN" && mkdir -p "$HOST_PLUGIN" && git -C "$PLUGIN_DIR" archive origin/main | tar -x -C "$HOST_PLUGIN"
bundle install >/dev/null
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null
bundle exec rails runner "$PLUGIN_DIR"/dev/legacy/repro_0_0_3.rb 2>&1 | grep -v "^\s*from \|Gemfile\|While it\|You should\|Remove any"
echo '==> restoring the working tree'
rm -f db/schema.rb && bundle exec rake db:drop db:create db:migrate >/dev/null
rm -rf "$HOST_PLUGIN" && "$PLUGIN_DIR"/dev/sync.sh "$DIR" >/dev/null
bundle install >/dev/null
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows >/dev/null
echo restored
