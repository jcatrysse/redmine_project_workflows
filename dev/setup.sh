#!/usr/bin/env bash
# Set up a Redmine host installation with this plugin, for local testing.
#
#   dev/setup.sh [redmine-branch] [postgresql|mysql] [ruby-version] [target-dir]
#
# Defaults match the primary supported target (Redmine 5.1 on PostgreSQL).
# Ruby is selected through rbenv/mise if available, otherwise the ambient ruby
# is used. The database must already be running; see dev/README.md.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"

BRANCH="${1:-${REDMINE_BRANCH:-5.1-stable}}"
DB="${2:-${DB:-postgresql}}"
RUBY="${3:-${RUBY_VERSION:-}}"
DIR="${4:-${REDMINE_DIR:-$PLUGIN_DIR/.redmine/$BRANCH-$DB}}"

DB_NAME="${DB_NAME:-redmine_test_$(echo "${BRANCH}_${DB}" | tr -cd '[:alnum:]_')}"
DB_USER="${DB_USER:-redmine}"
DB_PASS="${DB_PASS:-redmine}"

# rbenv being on PATH does not put its shims there, and without the shims the
# ambient ruby runs regardless of RBENV_VERSION -- which fails late, on a
# Gemfile ruby requirement, rather than here.
rbenv_shims() {
  if command -v rbenv >/dev/null 2>&1; then
    rbenv root 2>/dev/null | sed 's:$:/shims:'
  elif [ -d /opt/rbenv/shims ]; then
    echo /opt/rbenv/shims
  fi
}

if [ -n "$RUBY" ]; then
  export RBENV_VERSION="$RUBY"
  SHIMS="$(rbenv_shims)"
  [ -n "$SHIMS" ] && export PATH="$SHIMS:$PATH"
fi
export RAILS_ENV=test

echo "==> Redmine $BRANCH / $DB / $DIR"

if [ ! -d "$DIR/.git" ]; then
  mkdir -p "$(dirname "$DIR")"
  git clone --quiet --depth 1 --branch "$BRANCH" https://github.com/redmine/redmine.git "$DIR"
fi
cd "$DIR"

case "$DB" in
  postgresql)
    cat > config/database.yml <<YML
test:
  adapter: postgresql
  database: $DB_NAME
  host: ${DB_HOST:-localhost}
  port: ${DB_PORT:-5432}
  username: $DB_USER
  password: $DB_PASS
  encoding: unicode
YML
    ;;
  mysql|mysql2|mariadb)
    cat > config/database.yml <<YML
test:
  adapter: mysql2
  database: $DB_NAME
  host: ${DB_HOST:-127.0.0.1}
  port: ${DB_PORT:-3306}
  username: $DB_USER
  password: $DB_PASS
  encoding: utf8mb4
YML
    ;;
  *) echo "unknown database '$DB'" >&2; exit 1 ;;
esac

# RSpec is not part of Redmine's own Gemfile.
if ! grep -q rspec-rails Gemfile.local 2>/dev/null; then
  cat >> Gemfile.local <<'GEM'
group :test do
  gem 'rspec-rails'
  gem 'rails-controller-testing'
end
GEM
fi

"$PLUGIN_DIR/dev/sync.sh" "$DIR"

bundle config set --local without 'development'
bundle config set --local path 'vendor/bundle'
bundle install --jobs "$(nproc 2>/dev/null || echo 2)"

bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake redmine:plugins:migrate

echo "==> ready: $DIR  (run: dev/run.sh $DIR)"
