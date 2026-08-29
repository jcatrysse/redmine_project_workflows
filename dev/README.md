# Local test environments

The plugin has no tests of its own that can run standalone: every spec boots a
real Redmine host application. These scripts create such a host, sync the
working tree into it and run the suite.

`dev/` is the **only** supported way to build a host for this plugin. If you find
another set of setup scripts in a checkout — a `.codex/` directory existed until
2026-08-27 — it is stale: it named Redmine 6.0 as supported and 7.0 not at all,
and it put the host in a different place from the one `dev/run.sh` looks in.
Recover it with `git log -- .codex` if you need to, but do not build from it
(finding F08).

## Prerequisites

* `git`, `rsync`, a C toolchain, and the client headers for the database you
  want to use (`libpq-dev` for PostgreSQL, `libmysqlclient-dev` /
  `libmariadb-dev` for MySQL and MariaDB).
* A running database server, and a `redmine` account that may create databases:

  ```sh
  # PostgreSQL
  sudo -u postgres psql -c "CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';"

  # MySQL / MariaDB
  mysql -uroot -e "CREATE USER 'redmine'@'localhost' IDENTIFIED BY 'redmine';
                   GRANT ALL PRIVILEGES ON *.* TO 'redmine'@'localhost' WITH GRANT OPTION;"
  ```
* A Ruby matching the Redmine branch under test. `rbenv` is used when a version
  is passed; otherwise the ambient Ruby is used.

  | Redmine | Rails | Ruby used here |
  | ------- | ----- | -------------- |
  | 5.1     | 6.1   | 3.2            |
  | 6.1     | 7.2   | 3.3            |
  | 7.0     | 8.1   | 3.3            |

## Usage

```sh
# clone Redmine, install gems, create and migrate the database
dev/setup.sh 5.1-stable postgresql 3.2.6

# sync the working tree and run the specs (repeat after every edit)
dev/run.sh .redmine/5.1-stable-postgresql

# a single file, or any other rspec argument
dev/run.sh .redmine/5.1-stable-postgresql plugins/redmine_project_workflows/spec/services
```

`setup.sh` takes `[redmine-branch] [postgresql|mysql] [ruby] [target-dir]` and
defaults to Redmine 5.1 on PostgreSQL, under `.redmine/` in this repository.
`DB_NAME`, `DB_USER`, `DB_PASS`, `DB_HOST` and `DB_PORT` override the connection.

The plugin is copied rather than symlinked: the specs resolve
`config/environment` relative to their own real path, which a symlink breaks.

### The one gate the suite cannot run

The row and column actions on a workflow matrix (WP5), and the counter and undo
behind them (WP6), are JavaScript, and the suite is RSpec against a real Redmine:
it can assert the markup they are made of, and does, but it cannot run them.
`dev/check-bulk-js.mjs` is the other half — a hand-built DOM, the whole
`javascript_tag` block extracted from
`app/views/redmine_project_workflows/_bulk_script.html.erb`, and the **thirty-two**
things it has to get right.

The block is extracted whole rather than one function at a time, and it is
re-evaluated for every scenario that touches the undo stack. That stack is state
the script holds for the life of a page, so a scenario inheriting an earlier one's
stack makes every "there is nothing left to undo" check pass or fail on what was
left behind — which is exactly how the first version of those checks went wrong.

```sh
node dev/check-bulk-js.mjs
```

It needs only node, no Redmine and no database, and **CI runs it** — the
`Bulk action script` job in `.github/workflows/specs.yml`, beside `RuboCop`
(finding F07). It used to be a manual step, and whether it ran depended on
somebody remembering. Run it by hand as well when that function changes, because
it is a second of feedback rather than a push. Keeping the function small enough
for this to be sufficient is the reason it has no event wiring of its own.

### The four checks that must run before the suite

`maintain_test_schema` reloads `db/schema.rb` when the suite starts and wipes the
plugin's migration bookkeeping, after which a `VERSION=` migration silently does
nothing. So anything that migrates has to run **first**, on a database built from
core's migrations:

```sh
# from a stock database, per host
(cd .redmine/7.0-stable-postgresql && rm -f db/schema.rb \
   && RAILS_ENV=test bundle exec rake db:drop db:create db:migrate)

# 1. reversibility (INV-8): up -> 0 -> up leaves nothing behind
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
   redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0)

# 2. the backfill of migration 004, over a project that has rules
dev/check-backfill.sh .redmine/7.0-stable-postgresql 3.3.6

# 3. the upgrade rehearsal (WP15): the same migrations over the four shapes of
#    data an installation actually holds -- an own workflow, a duplicate rule
#    under it, an own EMPTY decision, and a scope whose author has been deleted
dev/check-upgrade.sh .redmine/7.0-stable-postgresql 3.3.6

# 4. the uninstall rehearsal (WP16): the procedure an administrator runs, through
#    the plugin's own rake tasks -- the refusal without CONFIRM=yes, the backup,
#    every migration reversed, the reinstall, and the restore
dev/check-uninstall.sh .redmine/7.0-stable-postgresql 3.3.6
```

All four are CI jobs as well, on every one of the nine cells. The third is the
one that says out loud what a **downgrade** costs: `VERSION=0` deletes every rule
that names a project, deliberately — without that, dropping the column would turn
every project's rules into rules of the workflow every project shares. An own
*empty* decision does not survive either, because the scope row is the only place
it was ever recorded.

The fourth is the answer to the third. It runs
`redmine_project_workflows:uninstall` and then
`redmine_project_workflows:restore`, and compares what came back with what was
there — the rules, the own *empty* decisions and the audit trail — so that
"there is a backup" is a thing that has been checked rather than believed.

## Continuous integration

`.github/workflows/specs.yml` runs the same scripts across Redmine 5.1 / 6.1 /
7.0 and PostgreSQL / MySQL / MariaDB on every push and pull request, plus three
gates per cell:

1. **The four migration checks above** — reversibility (up -> 0 -> up), the
   backfill, the upgrade rehearsal and the uninstall rehearsal — deliberately
   *before* the suite: `maintain_test_schema` reloads `db/schema.rb` when the
   suite starts and wipes the plugin's migration bookkeeping, after which
   `VERSION=0` silently does nothing and the checks prove nothing.
2. **`zeitwerk:check`** — Redmine pushes each plugin's `lib/` into the main
   autoloader with eager loading, so a misnamed constant only breaks in
   production.
3. **RuboCop**, once, in its own job.

Locally:

```sh
BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

## Spec layout

| Directory              | Purpose |
| ---------------------- | ------- |
| `spec/services`, `spec/models`, `spec/controllers`, `spec/helpers`, `spec/views` | Behaviour the plugin intends to provide. |
| `spec/integration`     | Guards that each Deface override still matches an anchor in the host's views. An unmatched override fails silently, so this must be checked per Redmine version. |
| `spec/characterization` | Behaviour that is currently **wrong**, pinned so that fixes are deliberate. When a defect is repaired, invert or delete its example — never make it green again. The directory is empty as of WP3, and the convention stands: a newly found defect that is not being fixed yet belongs here first. |
