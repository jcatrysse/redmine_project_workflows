#!/usr/bin/env bash
# Sync the working tree into a prepared Redmine installation and run the specs.
#
#   dev/run.sh [target-dir] [extra rspec args...]
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"
DIR="${1:-${REDMINE_DIR:-$PLUGIN_DIR/.redmine/5.1-stable-postgresql}}"
shift || true
[ -n "${RUBY_VERSION:-}" ] && export RBENV_VERSION="$RUBY_VERSION"
export RAILS_ENV=test
"$PLUGIN_DIR/dev/sync.sh" "$DIR"
cd "$DIR"
exec bundle exec rspec "plugins/$PLUGIN_NAME/spec" "$@"
