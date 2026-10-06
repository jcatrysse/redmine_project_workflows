#!/usr/bin/env bash
# Sync the working tree into a prepared Redmine installation and run the specs.
#
#   dev/run.sh [target-dir] [extra rspec args...]
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"
DIR="${1:-${REDMINE_DIR:-$PLUGIN_DIR/.redmine/5.1-stable-postgresql}}"
shift || true
if [ -n "${RUBY_VERSION:-}" ]; then
  export RBENV_VERSION="$RUBY_VERSION"
  # See dev/setup.sh: rbenv on PATH does not imply its shims are on PATH.
  if command -v rbenv >/dev/null 2>&1; then
    SHIMS="$(rbenv root 2>/dev/null)/shims"
  elif [ -d /opt/rbenv/shims ]; then
    SHIMS=/opt/rbenv/shims
  else
    SHIMS=""
  fi
  # See dev/setup.sh: a bare `[ ... ] && ...` aborts under `set -e`.
  if [ -n "$SHIMS" ]; then
    export PATH="$SHIMS:$PATH"
  fi
fi
export RAILS_ENV=test
"$PLUGIN_DIR/dev/sync.sh" "$DIR"
cd "$DIR"
exec bundle exec rspec "plugins/$PLUGIN_NAME/spec" "$@"
