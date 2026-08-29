# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **WP16 is three quarters done.** Items 2, 3 and 4 of the last work package —
  a downgrade procedure, a scripted backup-aware uninstall, and release criteria
  written down — landed this session. **Item 1 is what is left**, and it is
  blocked on something small: see *Exact next step*.
- **What the plugin can do that it could not.** Uninstalling it no longer means
  losing every project workflow. Reversing the migrations deletes every workflow
  rule that names a project and drops the table that records which projects
  decided to run their own — both deliberate, established by WP15 — and between
  them they discard every project workflow on the installation. There are now
  three rake tasks: `backup` writes exactly that population to one JSON file,
  `restore` puts it back, and `uninstall` does the whole procedure in the order
  that makes it survivable — count what is about to be lost, say so, refuse
  without `CONFIRM=yes` typed in full, write the backup **and read it back**, and
  only then migrate.
- **The restore goes through the writers, not around them.** A backup file is
  data of unknown age from outside the application, so INV-2's whitelist stands
  between it and the `workflows` table exactly as it stands between a request and
  it. A status, tracker or custom field deleted since the export is refused there
  and counted in the report rather than written back as a row naming nothing.
- **The backup holds decisions, not only rules.** An own *empty* workflow — a
  project that deliberately permits nothing for a tracker and a role — is a scope
  row with nothing under it, and it is the one thing a downgrade loses without
  leaving a trace. A backup of rules alone would bring it back as inheritance,
  which is the exact confusion INV-3 exists to prevent.
- **The alpha warning stays**, and `docs/release-criteria.md` now says why in a
  form somebody can check: nine release criteria, four more for removing the
  warning, each with how it is checked and where it stands. Three are unmet, and
  one of them — "has run on a real installation, with real data, for a stated
  period" — is not something this repository can answer about itself. That one is
  Jan's.
- **Nothing else a user can do has changed**, and nothing has been released:
  0.1.6, unreleased; `main` carries 0.0.3 and there is still no tag.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. The environment minted
  `claude/docs-review-rrs8vx`; `git checkout -B claude/dev origin/claude/dev` was
  the whole rescue. Sixth session in a row. Always reset the local ref from
  `origin/claude/dev` rather than trusting it.

## What this session produced

One commit, green on two local hosts and one MariaDB host, and lint-clean.

### `WP16 items 2-4` — the backup, the uninstall, and the criteria

**The two services.**
`lib/redmine_project_workflows/services/workflow_backup.rb` exports; 
`workflow_restore.rb` imports. The file is JSON — reading a backup is
`JSON.parse`, which builds no objects, where `YAML.load` of a file an operator
was told to keep somewhere safe is a much larger promise. It holds the scope rows
and the rules under them, plus the *names* of the projects, trackers, roles and
statuses they refer to, so that the file can be read by whoever has to decide
whether to restore it; nothing matches on those names, because ids are what a
rule is made of and a renamed project is still the same project.

The generic workflow is **not** in it. Nothing in these migrations puts a
`project_id IS NULL` row at risk, and restoring one would be a generic write,
which INV-1 says a project restore must never be.

**What the restore does, in the order it does it.** Load the referents once
(projects, trackers, roles, the users the audit columns name, and which
combinations already have a decision) — asking per combination would be six
queries per row of a file that can hold one per project, tracker and role on the
installation. Then create the missing scopes, **grouped** one call per (tracker,
role, rule type) whatever the number of projects, because that is the call that
takes a lock. Then one writer call per combination, which is irreducible: a
writer call covers one project and the rules of two projects are not the same
rules. Then the audit columns, from the backup rather than from whoever ran the
task.

Deliberately **not** one transaction over the whole file: each writer call has
its own, which is where the locks belong. A restore interrupted halfway has done
half its work, and running it again finishes the job — a combination already
restored is one the database has a decision for, which the default leaves alone.

**The one way a restore is not byte-for-byte:** duplicate rows, which a database
from before 0.1.6 can carry, come back as one row. The payload the writers take
is a matrix and a matrix has one cell. That is the same repair the deduplication
task performs and it cannot change what a workflow permits.

**The rake tasks** are in `lib/tasks/redmine_project_workflows.rake`, but their
*bodies* are in `lib/redmine_project_workflows/tasks.rb`: RuboCop does not inspect
`.rake` files and neither can a spec load one usefully. Moving them is what
brought `Rails/Output` and `Rails/Exit` to bear, and both are excluded for that
one file with the reason — a rake task's user interface *is* its standard output
and its refusal *is* a non-zero exit.

**`dev/check-uninstall.sh`**, a new CI job on all nine cells, in four legs: the
refusal (no `CONFIRM=yes` changes nothing and writes no file), the uninstall
(backup, then every migration reversed, then the host checked to be stock), the
reinstall (migrate up, restore, and all four seeded shapes compared with what was
there before), and a second restore that must change nothing — because an
operator who is not sure whether it worked will run it twice.

**The documentation.** `README.md` § *Upgrading and uninstalling* is now three
sections — backing up, uninstalling, and coming back — opening with the sentence
WP15 established and naming the own *empty* workflow as the thing a downgrade
loses silently. `docs/release-criteria.md` is new. `dev/README.md`'s "three
checks that must run before the suite" is now four.

## Evidence

Everything below was executed in this container.

| Gate | Result |
|---|---|
| Plugin suite, Redmine 7.0 and 5.1 on PostgreSQL 16, and 7.0 on MariaDB 10.11 | **1,251 examples, 0 failures** on each. Was 1,221 at the start of the session. |
| RuboCop through `.github/lint/Gemfile` | **152 files, no offences** |
| `rake zeitwerk:check` | All is good! |
| `node dev/check-bulk-js.mjs` | bulk action script OK |
| `dev/check-backfill.sh`, `dev/check-upgrade.sh`, `dev/check-uninstall.sh` | green on every host, each from a database rebuilt from **core** migrations first |
| Red-on-old-code | verified by mutation, one at a time, re-running the two new spec files after each: `copy_generic: false` flipped to `true` in the restore (1 red — the own *empty* workflow comes back with a copied generic rule in it), the audit stamp removed (1), and `confirm!` moved after the backup in the uninstall (1 — a refused run leaves a file behind). All three reverted. |
| CI | run **182** is the head (`162de21`) and is green on **all eleven jobs**, the new *Uninstall and restore rehearsal* step included on every one of the nine cells |

**One weakness this session found in its own gate, and fixed.**
`dev/check-uninstall.sh`'s first leg asserted only that the uninstall *failed*
without `CONFIRM=yes` — and it passed on a host the working tree had never been
synced into, where the rake task did not exist and rake exited non-zero for that
reason instead. It now greps the output for the refusal itself and for the
sentence naming what was at stake.

## Exact next step

**WP16 item 1 — an upgrade rehearsal from the previous release**, which is the
last thing in the plan.

`dev/check-upgrade.sh` already rehearses the migration path from `VERSION=3` —
where an installation on 0.0.3 stands — over populated data, on all nine cells.
What it cannot do is run the **code** of that release, which is the half that
would catch a migration file edited after it shipped.

**It is blocked on one small thing: the repository has no tags at all.** `main`
carries 0.0.3. Tagging that commit `v0.0.3` unblocks it, and then the script
wants a second mode: check the tag out into a scratch directory, install *that*
plugin into a host, populate it, then swap the working tree in and migrate up.

A tag is a release act rather than a code change, which is why this session did
not create one — see *Open choices*. If Jan says go ahead, it is one command and
then the script.

After that, `docs/release-criteria.md` is the checklist for the release itself.

## Open choices

- **Choice:** the repository has **no git tags**, so "upgrade from the previous
  release" has no previous release to check out — which is release criterion R5,
  and blocks the last item of the last work package.
  - **Options:** A) tag the commit on `main` that carries 0.0.3 as `v0.0.3`, and
    tag every release from now on. B) leave it, and accept that R5 is met only
    from 0.1.6 onwards, once *that* is tagged.
  - **Recommendation:** **A.** It costs one command, it is what makes the *next*
    release's upgrade rehearsal possible at all, and 0.0.3 is what real
    installations are actually running — so it is the version an upgrade
    rehearsal most needs to start from.
  - **Urgent?** no — nothing is blocked but WP16 item 1, and no code depends on
    it. This session did not do it because pushing a tag is a release act and
    `main` is Jan's.

- **Choice (carried, unchanged):** removing the *alpha* warning. Criterion A3 —
  "has run on a real installation, with real data, for a stated period" — is not
  something this repository can answer. `docs/release-criteria.md` lists the
  other twelve and their state.
  - **Urgent?** no — the warning stays until Jan says otherwise, which is the
    safe default.

## Rebuilding the 45-plugin host (for a release check, not for ordinary work)

The ordinary single-plugin hosts are in the next section and are what almost
every session wants. This recipe is only for repeating the compatibility run of
2026-08-28, which is the only environment in which the permission-ownership gate
can fail -- and it is the run that found the blocker WP10 fixed.

```bash
apt-get update -qq && apt-get install -y rsync libpq-dev
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB SUPERUSER PASSWORD 'redmine';\""
su postgres -c "psql -c 'CREATE DATABASE redmine_stack OWNER redmine;'"

git clone --depth 1 -b 5.1-stable https://github.com/redmine/redmine.git .redmine/5.1-stable-postgresql

# every plugin repository, cloned to a staging directory, then copied into
# plugins/<plugin id> -- the DIRECTORY NAME MUST BE THE ID from
# Redmine::Plugin.register, which differs from the repository name for
# redmine_tags (-> redmineup_tags), redmine_plugin_computed_custom_field
# (-> computed_custom_field) and bless-this-redmine-sso.
# Private repositories need `add_repo` before the clone will authenticate.

# three plugins need a non-default branch on 5.1 (F08), and two need an edit
# before the host will boot at all (F05, F06). The findings file lists all five.

RAILS_ENV=production bundle install
RAILS_ENV=production bundle exec rake generate_secret_token db:migrate redmine:plugins:migrate
```

Traps met while doing it, all of them costing time:

- **`pkill -f "rails server"` does not kill the server.** The process is
  `puma`, and the pattern misses it — so an edit "took effect" against a server
  still running the old code, and the first run of the F03 experiment reported
  a **false negative** (200 instead of 500). `pkill -f puma`, then verify with
  `ps aux | grep [p]uma`.
- **A backgrounded `rails server` started from a tool call gets killed with the
  call.** Write a one-line launcher script and start it with
  `(setsid nohup ./start_server.sh > log 2>&1 < /dev/null &)`.
- **`rspec` disappears from the bundle when plugins are removed.** RSpec comes
  from a *neighbouring plugin's* `Gemfile` on this host, so moving plugins aside
  to get a baseline breaks the suite runner itself. Put the `group :test` block
  in the host's `Gemfile.local` (what `dev/setup.sh` does) before bisecting.
- **Bisect by renaming `init.rb` to `init.rb.off`, not by moving directories.**
  Moving a directory changes the resolved bundle; renaming `init.rb` leaves
  `Gemfile`s in place, so no `bundle install` is needed between runs. Note that
  failure counts are **not monotone** — disabling a plugin others depend on adds
  failures — so bisect one failing example, not the whole suite.
- **Redmine 5.1 has no `assets:precompile`.** It serves static files from
  `public/`. `rake assets:precompile` aborts with *"Don't know how to build
  task"*, which reads like a broken host and is not.
- **Plugin `app/overrides` directories break Zeitwerk eager loading**, because
  Redmine puts every plugin's `app/*` on the eager-load path and deface's own
  railtie only excludes railties' copies, not plugins'. That is what
  `redmine_base_deface` exists to do.

## Development environment (rebuild from scratch in a fresh session)

```bash
# packages the container does not have
apt-get update -qq && apt-get install -y rsync libpq-dev

# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (about two minutes each; run them in the
# background in parallel). Two are enough for ordinary work.
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/setup.sh 7.0-stable postgresql 3.3.6
dev/setup.sh 6.1-stable postgresql 3.3.6

# A MySQL-family cell, worth the four minutes whenever a change touches SQL
# text -- six of the nine CI cells are MySQL or MariaDB and no PostgreSQL host
# can see what they see. This session's raw INSERT ... SELECT is exactly that
# case, and it was run here before the commit.
apt-get install -y mariadb-server libmariadb-dev
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld
nohup mariadbd --user=mysql --datadir=/var/lib/mysql \
  --socket=/run/mysqld/mysqld.sock > /tmp/mariadbd.log 2>&1 &
sleep 12 && mariadb --socket=/run/mysqld/mysqld.sock -e "SELECT VERSION()"
mariadb --socket=/run/mysqld/mysqld.sock -e "
  CREATE USER IF NOT EXISTS 'redmine'@'%' IDENTIFIED BY 'redmine';
  CREATE USER IF NOT EXISTS 'redmine'@'localhost' IDENTIFIED BY 'redmine';
  GRANT ALL ON *.* TO 'redmine'@'%'; GRANT ALL ON *.* TO 'redmine'@'localhost';
  FLUSH PRIVILEGES;"
dev/setup.sh 7.0-stable mysql 3.3.6
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-mysql

# the migration gates, BEFORE the suite, per host. RAILS_ENV=test has to be in
# the same invocation. If the suite has already run on that host, the database
# has to be rebuilt from CORE migrations first, or this proves nothing:
#   rm -f db/schema.rb && RAILS_ENV=test bundle exec rake db:drop db:create db:migrate
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows)
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0)
# leftovers must be [] AND schema_migrations must hold no '%-%' rows
dev/check-backfill.sh .redmine/7.0-stable-postgresql 3.3.6

# WP15's upgrade rehearsal: the same migrations over the four shapes of data an
# installation actually holds, plus the downgrade and what it costs. Needs the
# same stock-database precondition as the two above.
dev/check-upgrade.sh .redmine/7.0-stable-postgresql 3.3.6

# WP16's uninstall rehearsal: the procedure an administrator runs, through the
# plugin's own rake tasks -- refusal, backup, every migration reversed,
# reinstall, restore, and a second restore that must change nothing. Same
# precondition again.
dev/check-uninstall.sh .redmine/7.0-stable-postgresql 3.3.6

# sync the working tree and run the suite
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-postgresql
RUBY_VERSION=3.2.6 dev/run.sh .redmine/5.1-stable-postgresql

# one spec file only (dev/run.sh always runs the whole directory). NOTE the
# working directory persists between tool calls -- use absolute paths or the
# next command runs inside the host checkout.
dev/sync.sh .redmine/7.0-stable-postgresql
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rspec \
  plugins/redmine_project_workflows/spec/models/project_workflow_copy_spec.rb)

# what the screen does on Redmine's OWN default data, which the fixtures are not.
# This is how F03 was measured, before and after. The test database already holds
# fixture rows, so the loader refuses until they are cleared -- inside a
# transaction that is then rolled back, so the database is left as it was.
# `include Redmine::I18n` is load-bearing: without it `l()` is missing and the
# backtrace points at Thor.
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rails runner '
  include Redmine::I18n
  include ProjectWorkflowGraphsHelper
  def project_workflow_status_label(status, id) = status ? status.name : "New issue"
  ActiveRecord::Base.transaction do
    [WorkflowRule, Issue, Tracker, IssueStatus, Enumeration, Role, Member].each(&:delete_all)
    ActiveRecord::Base.connection.execute("DELETE FROM projects_trackers")
    ActiveRecord::Base.connection.execute("DELETE FROM member_roles")
    ProjectWorkflowScope.delete_all
    Redmine::DefaultData::Loader.load("en")
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
    # ... build a project, run WorkflowGraphQuery.new(project:, tracker:, role_ids:) ...
    raise ActiveRecord::Rollback
  end')

# the JavaScript gate (also a CI job)
node dev/check-bulk-js.mjs

# eager-load check, worth running whenever a directory is added under lib/
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rake zeitwerk:check)

# lint (rubocop's binaries are not on PATH by default in this container)
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle install
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant.

## Known traps

Everything below cost time at least once. **This session's are first**, then the
run that stood up a 45-plugin host, then everything carried forward.

- **A gate that checks only an exit status passes on a broken host.**
  `dev/check-uninstall.sh`'s refusal leg asserted that
  `rake redmine_project_workflows:uninstall` **failed** without `CONFIRM=yes`. It
  passed on the 5.1 host — where the working tree had never been synced in, the
  rake task did not exist, and rake exited non-zero saying *"Don't know how to
  build task"*. Assert on the output, not on the status: the refusal has a
  sentence and the sentence is what the leg is about. The same shape as the
  `value="2"` and INV-9 near-misses below — an assertion scoped more widely than
  the thing it is about.
- **RuboCop does not inspect `.rake` files.** Moving a rake task's body into a
  `.rb` file — which is the right move, because it is then reviewable and
  testable — brings `Rails/Output` and `Rails/Exit` to bear on code whose whole
  interface is `puts` and whose refusal is `abort`. Both cops are right about a
  web application and wrong about that one file. Exclude it in `.rubocop.yml`
  with the reason rather than reaching for `# rubocop:disable` eleven times.
- **`def foo(x) = y if cond` is not an endless method with a guard.** The
  modifier binds to the `def`, so the method is defined conditionally and its
  body is `y` unconditionally. Written that way,
  `WorkflowRestore::Referents#user_id` would have returned the id of a deleted
  user. Write the guard inside a normal `def`.
- **`a += b && c` parses as `a += (b && c)`.** `report.skipped_existing += 1 && nil`
  is `+= nil`, which raises. A `next` that also increments a counter needs two
  lines; the one-liner is not shorter, it is broken.
- **The working directory persists between tool calls** — this is in the recipe
  below and it still cost a call this session. After `cd`-ing into a host
  checkout to run one spec file, the next `python3 -` editing
  `lib/...` fails with *No such file or directory*. Use absolute paths, or `cd`
  back first.
- **A heredoc inside a heredoc needs different delimiters.** Editing a shell
  script that contains a `<<'PY'` block, from a `python3 - <<'PY'` call, ends the
  outer heredoc at the inner one's terminator and feeds the rest to bash. The
  symptom is a shell syntax error pointing at a line of Python.

- **`user.reload` does not clear a member's roles.** Core memoises them per
  project on the User instance (`@membership_by_project_id`), and `reload` leaves
  the memo alone. A spec that grants roles and then asks the same object sees the
  roles it had before — so `hot_path_scale_spec.rb` measured **one** role at both
  of its two sizes and passed, which is a comparison of nothing against nothing.
  Load a fresh `User.find(id)` instead. The general shape: an example that
  asserts "this did not grow" has to assert first that the thing which was
  supposed to grow did.
- **`roles_for_workflow` keeps only roles that answer `consider_workflow?`**,
  which is `add_issues || edit_issues` — not "is not builtin", which is what it
  looks like it should be. Roles created in a spec with `:view_issues` are
  filtered out by core before the plugin ever sees them. Same failure as above,
  reached a different way, and the two together took three attempts.
- **The first `<svg>` on a Redmine page is not the drawing.** Since 6.0 the
  layout is full of sprite icons, which are `<svg>` elements too, so
  `body[/<svg.*?<\/svg>/m]` extracts a tab icon and an assertion about the
  workflow drawing quietly becomes an assertion about that. Anchor on the class
  the partial writes. Same family as the `value="2"` and INV-9 near-misses below:
  an assertion scoped to the page rather than to the element.
- **An `OR` of exact triples and an `IN` per column are indistinguishable when
  the test data varies only one column.** The batching spec's padding first used
  one tracker and one role, so rewriting `each_batch_predicate` as a cross
  product — the plausible wrong repair — left every example green. Vary all three,
  and include a combination that lies inside the cross product and in no named
  triple.
- **A `js` format request needs `xhr: true`.** Without it Rails' cross-origin
  protection answers `ActionController::InvalidCrossOriginRequest` rather than
  rendering, which reads like a routing or authorization problem and is neither.
- **`css_select` takes one argument.** The `('selector', value)` form that
  `assert_select` accepts for `[href=?]` interpolation is not the same method:
  `css_select` reads a first String argument as the *root* to search in, and
  fails with `undefined method 'document' for an instance of String`. Interpolate
  the value into the selector yourself. Its return value is a `NodeSet`, which
  answers `#to_s` but not `#join` — which is worth knowing because
  RuboCop's `Style/MapJoin` will offer to autocorrect `map(&:to_s).join` into the
  latter, and the correction raises.
- **A rehearsal that fails is the point of a rehearsal.** The first version of
  `dev/check-upgrade.sh` expected a `VERSION=0` round trip to give the project
  rules back, and found one rule where it expected four. Migration 001's `down`
  deletes every rule naming a project, deliberately. The instinct to "fix the
  script" was wrong: the script was right and the expectation was, which is how
  the downgrade's real cost came to be written down at all.
- **A concurrency test that pauses in the wrong place proves nothing, and looks
  like it proves everything.** The example for F07 pauses one connection and lets
  the other run. Pausing it *before* its DELETE gives **one** row with the lock
  and one row without it: under READ COMMITTED the second DELETE sees the first
  connection's committed row and removes it, so the interleaving that produces a
  duplicate never happens. The duplicate needs both connections to find nothing
  to delete, so the pause has to be held open **between the delete and the
  insert**. Written the first way it would have been a green example asserting
  nothing at all — and it would have gone on being green after somebody removed
  the lock.
- **A comment explaining why a gate does not apply can trip the gate.**
  `plugin_conventions_spec` greps `{app,lib,db}` for the sentence *"INV-4's one
  deliberate exception"* and asserts exactly one file carries it. A new service
  whose comment quoted that phrase in order to say *this is not that* became a
  second hit. A gate that greps for a **sentence** is stronger than one that
  greps for a word (see the `fifteen`/`five` trap below) and this is its cost:
  the sentence is now reserved, and a comment must name the thing some other way.
- **A partial rendered lazily from one screen's markup is simply absent from the
  other screen.** `_bulk_script` was rendered by whichever row or column header
  came first, which is fine while only the transitions matrix needs it. The field
  permissions matrix has no row or column actions, so nothing on it ever rendered
  the script — and a new `onsubmit` handler added to *both* forms would have
  called an undefined function on one of them. Ask which screens actually reach
  the lazy call before adding a second caller to the thing it renders.
- **`include('value="2"')` over a whole page is not an assertion about a project
  selector.** A project id is also a tracker id, a role id and a status id, so the
  first version of "an archived project is not offered" failed against markup that
  had nothing to do with it. Extract the `<select>` the assertion is about and
  scan its options. Same family as the INV-9 near-misses below: an assertion
  scoped to the page rather than to the element.
- **`I18n.t(key)` leaves `%{count}` alone when no `count:` is given, rather than
  raising.** `I18n::Backend::Base#translate` only interpolates when the options
  hash has something in it, so a locale string written for JavaScript to fill in
  comes back with its placeholder intact. That is what the data attributes on the
  matrix forms rely on; it reads like a bug waiting to happen and is not one.
- **`rake db:drop db:create db:migrate` does not give you a stock database if
  `db/schema.rb` is still there.** On the MariaDB host, `db:migrate` on the empty
  database **loaded `schema.rb`** — which a previous suite run had dumped *with*
  the plugin's columns in it — while leaving `schema_migrations` without the
  plugin's dashed rows. The next `redmine:plugins:migrate` then died with
  *"Duplicate column name 'project_id'"*, which reads like a broken migration and
  is a stale dump. The recipe below already says `rm -f db/schema.rb` first;
  this is what happens when you skip it.
- **A table whose rows record no event should not have timestamps, and
  `Rails/CreateTableWithTimestamps` will ask for them anyway.** `created_at` on a
  lock row would be "the first time anybody saved this combination", which nothing
  reads or shows, and `updated_at` would never change — two columns that would
  read as an audit trail beside the real one on `project_workflow_scopes`.
  Disabled inline with the reason, which is this repository's idiom for a cop
  that is wrong about a specific row rather than about the rule.

- **A gate that greps a document for a word stops being a gate when the word
  becomes a common one.** INV-9's count assertion read
  `expect(document.downcase).to include('fifteen')`, which was strong: no
  document in this repository says "fifteen" about anything else. ADR-003 took
  the count to *five in three files*, and both of those words appear in
  `CLAUDE.md` and `docs/design.md` for a dozen unrelated reasons — so the gate
  would have gone on passing over any count whatsoever, silently, from the
  moment it was changed. Assert the **sentence** a reader actually reads
  (`five view overrides`, `in three files`), and check it by editing the
  document to a wrong count and watching it fail. A gate can be weakened by a
  change to the *thing it measures* rather than to itself.
- **`ActionView::Template#source` is not the file on disk once a page has been
  rendered.** Deface's `encode!` calls `source.replace(new_source)` — it mutates
  the string in place with the overrides applied. A check asking "does this
  override's selector still match its view?" against that string would sometimes
  be asking about a view that already carries the override, i.e. answering its
  own question. Read the file at `template.identifier` instead; the resolver is
  still the right way to *find* it, because a plugin can ship its own copy of a
  core view and a glob over `view_paths` would pick the wrong one.
- **A `type: :view` spec has no controller, so a plugin's `helper` declarations
  do not apply to it.** `spec/views/workflows/copy.html.erb_spec.rb` moved to
  the plugin's own copy view and immediately raised
  `undefined method 'project_workflows_icon_link'` — the plugin's screens name
  their helpers in the *controller's* class body, and rspec's view specs build a
  view context from `ApplicationController`'s helpers. Drive such a screen
  through its controller with `render_views` instead, which also gives it the
  instance variables the screen actually needs.
- **A partial rendered from two controllers cannot move into one controller's
  view directory.** When the Deface overrides went, three of the four partials
  they rendered became exclusive to `project_workflow_rules/` and moved there.
  `_bulk_undo` did not: the project matrices render it too, and `_bulk_script` is
  reached from a helper called out of *core's* `workflows/_form`. Those stay in
  the neutral `app/views/redmine_project_workflows/` namespace, which is what
  that directory is for — a path that is not controller-scoped.
- **Moving a screen means grepping for every link into it, including the ones a
  spec already covers.** Four links still built `edit_workflows_path(project_id:
  [...])` after core's screens stopped reading a project. Three of them *had*
  assertions naming the old path, and those assertions went on passing because
  the code went on producing the old path — the specs were right about the code
  and both were wrong about the product. `grep -rn 'workflows_path' app/ lib/`
  found all four in one line; nothing else would have.

- **An INV-9 assertion can be satisfied by the *layout* rather than by the
  override.** The first version of the cross-link's example asserted
  `include('href="/project_workflow_rules"')` in the body of core's workflow
  page — which is true of **every** administration page whatever the override
  does, because WP12's `admin_menu` entry renders exactly that href into the
  `admin` layout. Deleting the link from the override left the example green.
  Scope such an assertion to the element the override writes into
  (`css_select('div.contextual a[href=...]')`), and never trust one that has not
  been watched to fail. This is the second INV-9 near-miss of the same shape, and
  both were markup the layout contributed.
- **A `layout` declaration puts a method on a controller that looks exactly like
  a copied core body.** `layout 'admin'` defines `_layout`, so a gate that
  discovers "what the plugin copied" from `instance_methods(false)` reports
  `WorkflowsController#_layout` — with core's definition pointing into the
  actionview gem, which reads as a spectacular drift and is nothing. A **class**
  in such a list is not a **module** in it: a class carries whatever the
  framework's macros wrote onto it. Rails marks its own with a leading
  underscore, which is the only reason this was cheap to filter.
- **"Is this module in the chain?" is the wrong question when two of your
  modules are.** `CoreMethodDigest.core_source` stepped once past the module it
  was asked about, which is right for one patch on one owner and wrong the
  moment a second module of the plugin's sits in the same ancestry — it then
  digests the plugin's own body and calls it core's, silently, in the gate whose
  entire job is to notice a changed core body. Walk down while the definition is
  yours; do not reason about attachment styles.
- **`l()` is not available in an RSpec example.** A controller spec that asserts
  a flash message against a locale key needs `I18n.t`; `l` is a view and
  controller helper. The failure is `NoMethodError` on the example group, which
  reads like a missing require.
- **A `back_url` in a login redirect is not information about the server.** An
  example asserting that two requests are indistinguishable compared whole
  `Location` headers and failed on 5.1 only — because 5.1 appends `back_url` and
  6.1 and 7.0 do not, and the parameter is the visitor's own request echoed back.
  Compare the status and the path; what would be a leak is a different *kind* of
  answer for the two ids.
- **A single-quoted YAML value cannot contain an apostrophe** unless it is
  doubled. Writing eight locale files from a script, `'Redmine's own workflow'`
  parses as a value followed by garbage. The sibling of the `place: a screen`
  trap already in this list: anything a script writes into YAML needs quoting
  *and* escaping.
- **The rubocop todo file's Group 1 rationale travels with a moved method, and
  the file name has to travel with it.** `field_permission_tag` is core's body
  and was excluded under `workflows_helper_patch.rb`; moving it to a helper of
  the plugin's own made it a new offence in a new file. The reason had not
  changed — only the path. Re-read the todo's own header before deciding a new
  offence is debt.

- **Redmine 5.1 offers exactly one locale under `RAILS_ENV=test`, and 6.1 and
  7.0 offer them all.** 6.1's and 7.0's `config/application.rb` set
  `config.i18n.available_locales` from core's own `config/locales/*.yml`; 5.1's
  does not. Measured on a 5.1 host: `I18n.load_path` holds 63 files including
  **two** `nl.yml`, and `I18n.available_locales` is `[:en]` all the same — so
  `I18n.t(key, locale: 'nl')` raises `I18n::InvalidLocale` and any page renders
  in English however the user's language is set. A spec that renders in a
  non-English locale has to ask the host which locales it has
  (`%w[...] & I18n.available_locales.map(&:to_s)`), or it is red on three of the
  nine cells. Whether the same holds outside the test environment was **not**
  measured; it is core's own configuration either way and applies to core's
  translations exactly as to this plugin's.
- **A locale spec that only asserts "no missing translation" cannot fail.** If
  the language never took effect the page renders in English, where nothing is
  missing. Assert the *translated* string first, then the absence. Doing that is
  what found the trap above.
- **"Does the gate cover X?" has to ask the measurement, not the table.** The
  example pinning the new singleton coverage asked
  `digests_for(host_minor).keys` — the checked-in manifest — and stayed green
  with the singleton targets removed from `CoreMethodDigest`, because the table
  still listed what the gate had stopped measuring. Ask
  `CoreMethodDigest.digests.keys`. Found by reverting `TARGETS` on a host and
  watching the example *not* fail; that is now three guards in two sessions that
  passed by accident, and every one was found by reverting and running.
- **A patch can be correctly applied while its own module is in no chain at
  all.** `IssuesControllerPatch.apply!` puts `ProjectWorkflowMapsHelper` into
  `IssuesController`'s helper chain and nothing of its own — there is no core
  method to override, only a helper a Deface override calls from a view core
  owns. A check asking whether the *patch* is attached reported it as missing.
  Ask what the patch actually attaches.
- **`Redmine::Plugin#menu` forwards its options verbatim and sets no `plugin:`
  key.** So an `admin_menu` entry's `icon:` resolves against **core's** sprite
  sheet, which is what you want (`summary` is in it on 6.1 and 7.0), and passing
  `plugin:` yourself would send `sprite_icon` looking for a sheet in this
  plugin's assets, which it does not ship. 5.1's `MenuItem` has no `icon`
  attribute and does not raise on an unknown option, so passing both `icon:` and
  `html: { class: 'icon icon-summary' }` is right on all three — 5.1 draws the
  picture behind the class, 6.0 and later draw the sprite.
- **`... | tail -3` hides a failing suite, and `&&` does not stop.** The exit
  status the shell sees is `tail`'s, which is 0 whatever rspec did, and three
  lines of a failure report look exactly like three lines of a success report.
  A whole `for` loop over three hosts reported success with one host red. Grep
  for `examples,` **and** `Failed examples` rather than tailing.
- **Redmine has no neutral message box, and `.nodata` is not one.** `.nodata`
  and `.warning` are a single rule in `application.css` on 5.1 and on 7.0 — the
  same amber background and border — so `.nodata` is a *warning* wearing another
  name, and putting a reassuring sentence in one says the opposite of the
  sentence. A bare `<div class="notice">` is not the alternative either: the
  green box is `div.flash.notice` and needs the flash class. Good news gets a
  plain paragraph; the amber box is for the states that are not good news, with
  the text carrying which one it is.
- **A colon followed by a space inside an unquoted YAML scalar breaks the
  file.** Appending locale lines with a heredoc is fine until one sentence
  contains `place: a screen`, and then `Psych::SyntaxError: mapping values are
  not allowed in this context` names a column, not a key. Quote every value
  written by a script.

- **A feature test on a method name is not a version test, and a neighbouring
  plugin can make it lie.** `respond_to?(:sprite_icon)` is this plugin's answer
  to "does the host draw SVG icons?", and on Redmine 5.1 both the `redmineup`
  gem and `redmine_ai_triage` define that method as a back-compatibility shim.
  The plugin then takes the Redmine 6 branch on a Redmine 5 host. When the
  question is really "which Redmine is this?", ask
  `Redmine::VERSION::MAJOR` — which is what `redmine_ai_triage` does, three
  files away in the same host. This is F02.
- **Two plugins can claim the same permission name, and the loser is silent.**
  `Redmine::AccessControl` keeps a flat array and `permission(name)` returns the
  **first** match; plugins load in alphabetical directory order. The plugin that
  loses does not warn, does not raise, and does not appear anywhere in a log —
  its screens simply answer 403, administrators included, because
  `Project#allows_to?` is consulted *before* `User#allowed_to?` reaches its
  `return true if admin?`. The only visible trace is a duplicated checkbox with
  a duplicated HTML id on the role form. This is F01, and it is why the fix has
  to carry a spec asserting the registration *won*.
- **A spec that restates the production code's condition can be wrong in the
  same direction as the code, and then it agrees with itself.**
  `core_renders_sprites?` in two spec files is the same
  `respond_to?(:sprite_icon)` expression the helper uses. When a neighbour made
  it answer wrongly the specs did fail — but only because the *rendering* also
  changed; had both sides been wrong in the same way the suite would have stayed
  green over broken output. Ask the production helper, or ask a fact.

The rest is carried forward.

- **A cost asserted from memory can kill a good idea.** The first answer to F01
  ruled out a checkbox on core's copy form because it would mean a sixteenth
  Deface override (INV-9). It would not: `app/views/projects/copy.html.erb`
  renders `call_hook :view_projects_copy_only_items, project:, f:` inside that
  fieldset on 5.1, 6.1 and 7.0. The plugin reaches most of Redmine's screens
  through Deface, so "another screen, therefore another anchor" felt like
  knowledge; it was a generalisation, and the view was never opened. **Before
  costing a change to a core screen, read that screen's ERB and grep it for
  `call_hook`** — core has dozens of them and they cost nothing.
- **`Redmine::Hook::Listener` is not in `lib/redmine/hook.rb`.** That file holds
  the registry and the `call_hook` helper only; `Listener` and `ViewListener`
  are `lib/redmine/hook/listener.rb` and `lib/redmine/hook/view_listener.rb`.
  Reading hook.rb alone suggests the base class is gone. `Listener` includes
  `Singleton` and registers on `inherited`, and `add_listener` **raises** for a
  class that does not include it, so subclassing is the only supported route.
- **A view hook wants `ViewListener.render_on`, not a string built in Ruby.**
  `render_on` renders a partial through `context[:hook_caller]` — the view — so
  the partial has `l`, `check_box_tag` and the hook's context as locals, and the
  plugin writes no HTML in Ruby. The context's `project` on the copy form is the
  **source** project, because core passes `project: @source_project` explicitly
  over `call_hook`'s default `@project`.
- **Adding any method that shadows a core method moves the core-drift gate to
  red, delegates included.** `Project#copy` calls `super` and does nothing else
  of substance, and the digest table still gained an entry per minor — correctly,
  because the gate reports "the copies **and** the delegates". Measure the digest
  on each host (`CoreMethodDigest.digests["Project#copy"]` in a `rails runner`)
  and add all three in the same commit; `dev/sync.sh` the host first or the
  runner reads the previous copy of the plugin and prints nil.
- **A window of lines is not a statement, and a grep that uses one can clear the
  very shape it exists to reject.** The first version of
  `plugin_conventions_spec.rb`'s INV-4 example asked whether `project_id`
  appeared within three lines of a `WorkflowPermission.where(...)`. It passed
  against the old `base_scope` shape — because the *next statement*, three lines
  down, adds the project_id to a copy of that relation. A relation and the
  statement that narrows it are two different things, and only the second one
  runs. Grow the match until its parentheses balance and ask about that. The
  first version was written, run against the reverted code, and seen to pass;
  that is the only reason it was caught.
- **An "answers the same as" assertion can pass because both sides are wrong the
  same way.** The example comparing a copied project's effective status list
  against the source's passed with the copy disabled, because the project's own
  rule named the same two statuses the generic workflow did — so an inheriting
  copy answered the same list. Give the overriding side a status the generic
  workflow never mentions, or the assertion is a tautology.
- **A `rails runner` probe of the graph needs `include Redmine::I18n`** before
  `include ProjectWorkflowGraphsHelper`, or `l()` is missing and the backtrace
  points at Thor rather than at the line. And `WorkflowGraphQuery.new` takes
  `role_ids:`, not `roles:` — the recipe further down this file had it wrong.
- **The fresh-container `claude/dev` trap below is real and it fired again this
  session.** Worth adding to it: `git checkout claude/dev` *before* resetting
  puts the unrelated history on disk, so every documentation file reverts to a
  months-old version at once and the editor shows a state that looks like
  somebody undid the project. Nothing is lost; `git checkout -B claude/dev
  origin/claude/dev` is the whole rescue. Tagging the stale head first
  (`git tag stale-local-claude-dev <sha>`) costs nothing and makes the reset
  obviously safe.

- **A screen that models "what the rules say" is not modelling "what Redmine
  does".** Core's fallbacks live *outside* the rule tables:
  `Issue#new_statuses_allowed_to` queries the workflow and then appends the
  tracker's default status when the answer came back empty. Reading the query
  core makes is not the same as reading the method that makes it, and the whole
  of finding F01 is the difference between the two. Read core's method to its
  last line before deciding what a table means.
- **Redmine's fixtures are not Redmine's shipped configuration**, and the
  difference is exactly where two of this round's findings lived. The test
  fixtures carry no workflow at all and every spec writes its own, usually
  including an entry rule; `redmine:load_default_data` writes 48 rules per
  tracker, **no** entry rule, and a *complete* graph. A screen that is only ever
  seen against fixtures is a screen nobody has seen. The probe is four lines and
  is in *Development environment* below: clear the tables inside a transaction,
  `Redmine::DefaultData::Loader.load("en")`, measure, `raise
  ActiveRecord::Rollback`.
- **"Red on the old code" needs the *right* break.** Reverting a whole file makes
  new examples fail with `NoMethodError`, which proves the API changed rather
  than that the behaviour did. The evidence worth writing down comes from
  breaking the **one branch that decides the behaviour** and leaving the API
  alone — here, forcing `fallback_status` to return `nil`, which turned 7 of 8
  new examples red and correctly left the negative one green. For a view, the
  whole-file revert *is* the right break, because a view has no API.
- **Changing what a result object counts turns green examples red, and widening
  the assertions is the wrong repair.** Adding one synthetic edge made eleven
  passing examples fail. Every one of them was about *which population was read*,
  so each was pointed at `stored_edges` — the collection it had always been about
  — and the new edge got assertions of its own. An example that quietly tolerates
  a new element is an example that has stopped saying anything.
- **`Metrics/ClassLength` counts dead code too.** `WorkflowGraphLayout` came back
  at 201/200, and four of those lines were a copy of `both_reachable?` that
  nothing in the file had ever called. Look for what is unused before looking for
  what to extract — and then extract anyway, because 200/200 is not a margin.
- **`<details>` is the whole disclosure widget** and needs no JavaScript, no
  stylesheet and no Redmine helper. Worth remembering in a plugin that ships no
  assets at all: the alternatives all do.
- **A regexp that spells a quote character is a PostgreSQL-only assertion.**
  PostgreSQL writes `FROM "workflows"`; MySQL and MariaDB write
  `` FROM `workflows` ``. A pattern with `"?` in it matched nothing on six of the
  nine CI cells, and this session shipped it twice before CI said so. Write
  `["`]?` or match the bare name. **The lucky half of it:** the assertion was
  `not_to be_empty`, so an empty list *failed*; the identical mistake under
  `to all(...)` goes **green** over an empty list and proves nothing at all for
  as long as it stands. Grep the specs for that shape before trusting one.
- **"Green on two PostgreSQL hosts" is two of nine, and the other seven include
  every MySQL cell.** Installing MariaDB in this container takes about four
  minutes end to end and the recipe is above. Do it whenever a change touches
  SQL *text* — a spec that reads a statement, a hand-written fragment, an
  assertion about a query plan.
- **`empty?` on a derived collection is rarely the question you mean.** The graph
  screen keyed "this project has its own empty workflow" on `edges.empty?`, which
  is equally true of a project inheriting a generic workflow nobody filled in.
  Whenever a sentence explains *why* a collection is empty, key it on the thing
  that decides the why — here the scope table (INV-3) — never on the emptiness.
  This is the fourth finding in four runs whose whole content is a check that
  asks something adjacent to what it needs to know.
- **404 is for "you named something that is not on offer", not for "there is
  nothing to offer".** A project nobody is a member of has no role to draw a
  workflow for, and answering 404 calls that a missing page. Render, and say what
  the state is — and note that the only reader who can *reach* such a project is
  an administrator, because emptying the membership takes away the permission a
  member would have read it with. A spec for that case has to log in as admin.
- **A `<title>` inside an `<svg>` is not the only `<path>` on a Redmine page.**
  An assertion that "the drawing has no arrow" written as
  `expect(response.body).not_to include('<path d="M ')` fails on core's own icon
  sprite, and then on the plugin's own arrowhead `<marker>`, which lives in
  `<defs>` whether anything uses it or not. Scope to the plugin's `<svg>`, and
  then to what makes a path an *arrow*: its `marker-end`.
- **Redmine caps an issue status name at 30 characters** (`validates_length_of
  :name, maximum: 30`), which is a useful number to know before sizing anything
  that holds one: WP9's node box holds two lines of sixteen. A spec that creates
  a longer status raises `Validation failed: Name is too long`, which reads like
  a bug in the thing under test and is a fixture problem.
- **SVG neither wraps nor measures text**, so anything drawn as `<text>` whose
  width the layout cannot know can run outside the `viewBox` and be clipped with
  no error anywhere. That is why WP9's band of unreachable statuses is separated
  by a dotted rule inside the drawing and captioned in HTML *below* it.
- **A `viewBox` built from node positions clips every curve that bows outside
  them**, silently. Measure the extent over the boxes **and** every point of every
  path; a cubic Bezier lies inside the hull of its four points, so control points
  are a sound bound. The gate for this was broken on purpose and watched to fail.
- **Dummy nodes are for the ordering pass *and* the routing pass.** Inserting a
  dummy in each layer a long edge crosses makes the ordering keep room for it —
  and then drawing that edge as one curve from end to end throws the room away
  and the curve passes through the box of the node in between. Route through the
  dummies.
- **Interpolating a number as `count:` in an I18n key turns it into a
  pluralisation.** `I18n.t(:some_key, count: 3)` makes I18n look for `one`/`other`
  subkeys under that key, and a plain string then answers "translation missing"
  in every language. Name the variable anything else.
- **The working directory persisted into a host checkout and stayed there for
  four tool calls**, so a `grep` of `.rubocop.yml` read *Redmine's* config —
  which has `Metrics: Enabled: false` and no `.github/lint/` at all — and very
  nearly produced a session that believed the size cops were off. The list has
  warned about this trap in three forms already; this is the fourth. `pwd` is
  cheap. Prefix every command with `cd /home/user/redmine_project_workflows &&`.

Everything from here down is carried forward from earlier sessions.

- **An `OR` of ActiveRecord relations does not put every predicate in every
  branch.** Rails factors out what all the branches share, so a statement built
  from four conditions on the same base scope names the base condition and the
  tracker **once**. Any assertion about "how many branches" has to count
  something that is genuinely per branch — here the `project_id` predicate —
  and the only way to know which is to print the SQL from a `rails runner`
  probe before writing the expectation.
- **`Issue#tracker=` asks the workflow nothing when the issue is on the old
  tracker's default status.** It sets `status = nil` on that branch and returns.
  So a query-count measurement, or any example about what a tracker change reads,
  needs an issue on a **non-default** status — and should say why in a comment,
  because the cheap branch makes a broken measurement look like a spectacular
  improvement (ten projects read as 2 statements instead of 22).
- **A one-element list in `where(project_id: [id])` renders as `= 1`, not
  `IN (1)`.** Harmless, but an assertion that greps for `IN` fails on the group
  that happens to hold one project. Match on the column name.
- **`git reset --hard origin/claude/dev` on a fresh container is right, and the
  divergence it discards is not local work.** This container's local
  `claude/dev` was five commits of the *unrelated* `main` lineage; `git checkout`
  reported "5 and 50 different commits each", which reads like something to
  preserve. `git merge-base --is-ancestor A B; echo $?` is the check that cannot
  lie — and the branch the environment minted (here `claude/docs-review-40quew`)
  already pointed at the real remote head, so nothing needed rescuing.

Everything from here down is carried forward from earlier sessions.

- **A gate that has never fired is a claim about nothing, and only a probe tells
  you which kind you have.** Three gates were built in the 0.1.4 session and all
  three were *deliberately made to fail* before being trusted. Two of the three were
  broken when first written and passed anyway: F03's oracle compared two empty
  arrays (see the next entry), and the override-name grep counted seventeen names
  for fifteen overrides. Neither would ever have failed. **Add the gate, then
  break the thing it watches and watch it fail** — with a real change, reverted
  afterwards, not a hypothetical.
- **An example that drives `Issue.new` is not testing the workflow you think it
  is.** A new record resolves transitions from core's `old_status_id = 0`
  pseudo-status, so a rule written out of a real status matches nothing and the
  answer is `[]`. Two `[]`s compare equal, so an oracle example passes while the
  code under test is deliberately broken. Use `Issue.create!` with a current
  status — and create it **before** arranging any rule, because a workflow rule
  can make the save fail.
- **`instance_methods(false)` silently omits what core made private.** Two of the
  methods this plugin shadows are private in core, one of them
  `Issue#workflow_rule_by_attribute`, which decides which fields are read-only or
  required. A reflection-driven gate has to take
  `private_instance_methods(false)` too, or it covers thirteen of fifteen and
  reports success.
- **A SHA256 of all digits is an Integer to YAML.** A digest table has to quote
  its values, or a comparison fails against every host for a reason that has
  nothing to do with the code. Found while probing the drift gate with a
  deliberately wrong all-zero digest.
- **An assertion over a file's whole text fails on the file's own comment.** The
  F12 gate asserted the `Gemfile` did not `include('rspec-rails')`; the `Gemfile`
  explains which gems were removed and names them. Read *declarations*, not text.
  The same trap in a different key: the F13 comment claimed "`grep secrets.` is
  empty" and thereby falsified itself.
- **"No subquery" and "the counts are equal" are the wrong gates**, and both were
  written before being run. F04's correct fix *keeps* an `IN` subquery — `IN` is
  already a semi-join — so the property is "no join, no `DISTINCT`, and the
  subquery does not select `workflows.id`". F10's two query counts are 5 and 3,
  the *small* selection being the more expensive, because a count query is
  skipped when there is nothing to count; the property is a bound. Assert the
  property you can defend, not the one the finding's headline suggests.
- **A new scenario inserted into `dev/check-bulk-js.mjs` between an existing one
  and the `cells` it depends on breaks it.** Exactly the state leak that file's
  own header warns about, met from the other direction. Append after the
  scenario that owns the variable, or `reset()` and build your own.
- **Six `Metrics` limits were crossed in the 0.1.4 session and all six were
  fixed by extracting.** They are already relaxed in `.rubocop.yml` with a stated
  rationale, so crossing one is a real signal. What came out of it, and all of it
  is a genuine improvement rather than placation:
  `Patches::WorkflowsControllerCopy` (the copy screen's four helpers),
  `RedmineProjectWorkflows::MatrixParams` (matrix parameter shaping),
  `RedmineProjectWorkflows::MatrixReporting` (what a write says and logs), and
  `Services::SanitizedPayload` — which was `sanitize_and_count` **duplicated in
  both writers**, so the cop found a real one-rule-in-two-places. Note that a
  module included into a controller must have only private methods.
- **`Rails/ActionControllerFlashBeforeRender` fires on a controller that reads
  its own `flash` back**, e.g. to append a second sentence. The cop is right to
  be suspicious: build a list of messages and assign once.
- **rspec-mocks refuses to stub from an `around` hook** — "the use of doubles
  outside the per-test lifecycle is not supported". For a logger, a real `Logger`
  over a `StringIO` in a `before` hook is better anyway: it asserts the text that
  reaches a log file, where a double would let a formatting change pass.
- **`css_select("label[for=?]", id)` is not a supported form** and raises
  `undefined method 'document' for an instance of String`. Interpolate:
  `css_select("label[for='#{id}']")`.
- **A `FOR UPDATE` statement's row ids travel as bind parameters**, so the SQL
  text cannot say which rows were locked. To assert *coverage* rather than mere
  presence, capture what the locking method returned.
- **A stray `rspec` process from an earlier tool call holds row locks and makes
  the next concurrency example hang.** A two-connection probe that had timed out
  once made the next run look like a deadlock in the fix. `pkill -f rspec` and
  check `pg_stat_activity` before diagnosing.
- **The nine-cell matrix cannot find a timezone defect, and
  `dev/check-backfill.sh` proves it.** That script has long asserted the
  backfilled timestamps are within 600 s of UTC, and it would have caught F09 —
  on a server whose own timezone is not UTC. Every database *container* CI runs
  defaults to UTC, so the drift is zero on all nine cells and always will be.
  Reading `AbstractMysqlAdapter#configure_connection` is what found it. Some
  classes of defect are not reachable by the matrix; know which.
- **A `cd` in a compound command persists and silently redirects the rest of the
  line.** A `cp` restoring a backed-up file after a host-directory `cd` wrote
  nothing and reported nothing useful, leaving the *old* code in the tree with
  the fix only in the scratchpad. Use absolute paths for a restore, always.
- **Neither half of the old timestamp trap was true**, and it is here as a
  correction because it stood in this list, in a migration comment and in
  `docs/DECISIONS.md`. It used to read "PostgreSQL will not cast a text literal to
  a timestamp inside a `SELECT` list, so the backfill uses `CURRENT_TIMESTAMP`".
  Measured on PostgreSQL 16.13: a bare quoted literal in the `SELECT` list of an
  `INSERT … SELECT` **is** coerced to the target timestamp column, no cast needed.
  And `CURRENT_TIMESTAMP` is UTC only on PostgreSQL. Build the timestamp in Ruby:
  `connection.quoted_date`, wrapped in the standard `TIMESTAMP '...'` type
  keyword, which all three accept (finding F09).
- **A scoped `prepend_before_action` DELETES the unconditional registration it
  looks like it is adding to.** ActiveSupport's callback dedupe compares only
  *kind* and *filter* — `Callback#duplicates?` → `matches?(kind, filter)` — and
  `only:` is stored as a separate `:if` condition, so
  `prepend_before_action :require_admin, only: [:edit, :update]` on
  `WorkflowsController` removes core's own unconditional `before_action
  :require_admin` and leaves `index`, `copy` and `duplicate` **ungated**. Read in
  the Rails source at `v6.1.7`, `v7.2.2` and `main`. Nothing in the plugin does
  this — the entry is here because it is precisely the "improvement" a session
  working on the administration screens' callback order reaches for. The safe fix
  is a **guard clause inside the patched finder**, which is what
  `find_trackers_roles_and_statuses_for_edit` now carries (finding F05):
  `User.current` is already correct there, because `ApplicationController`
  registers `user_setup` before `WorkflowsController`'s own callbacks on all
  three supported versions.
- **`say_with_time` prints a row count only if its block returns an Integer.**
  `execute` returns an adapter result object, so migration 003's DELETE from
  Redmine's own `workflows` table printed the elapsed time and no number at all.
  `connection.delete` returns the count (finding F20).

- **A fresh container's local `claude/dev` can have a history unrelated to the
  remote's.** `git pull --ff-only` then aborts with "Not possible to
  fast-forward", and `git status` reports a divergence — "5 and 50 different
  commits" — that looks like real local work to be preserved. It is not:
  `git merge-base claude/dev origin/claude/dev` printed **nothing**, and the two
  branches have different root commits. `git reset --hard origin/claude/dev`.
  What makes this dangerous is the diagnostic: piping an *empty* merge-base into
  `xargs git log --oneline -1` prints **HEAD**, which reads exactly like a merge
  base that happens to be the local head. Use
  `git merge-base --is-ancestor A B; echo $?` instead, which cannot lie.
- **A scoped `prepend_before_action` DELETES the unconditional registration it
  looks like it is adding to.** ActiveSupport's callback dedupe compares only
  *kind* and *filter* — `Callback#duplicates?` → `matches?(kind, filter)` — and
  `only:` is stored as a separate `:if` condition, not in the filter. So
  `prepend_before_action :require_admin, only: [:edit, :update]` on
  `WorkflowsController` removes core's own unconditional `before_action
  :require_admin` and leaves `index`, `copy` and `duplicate` **ungated**. Read in
  the Rails source at `v6.1.7`, `v7.2.2` and `main`. Nothing in the plugin does
  this — the entry is here because it is precisely the "improvement" a session
  working on the administration screens' callback order reaches for, and
  `docs/DECISIONS.md:93` had rejected it for a weaker reason. The fix that is
  safe is a **guard clause inside the patched finder**, which is what
  `find_trackers_roles_and_statuses_for_edit` now carries (finding F05):
  `User.current` is already correct there, because `ApplicationController`
  registers `user_setup` before `WorkflowsController`'s own callbacks on all
  three supported versions.
- **`dev/run.sh` needs `RUBY_VERSION` for the 5.1 host, and the symptom is a
  missing gem.** Without it the ambient Ruby 3.3.6 runs against a bundle
  installed under `ruby/3.2.0`, and the error is
  `bundler: command not found: rspec` — which reads as the Bundler-4
  executables-not-on-PATH trap below and is a wrong Ruby.
  `RUBY_VERSION=3.2.6 dev/run.sh .redmine/5.1-stable-postgresql`.
- **`Metrics/ClassLength`, `Metrics/ModuleLength` and `Metrics/AbcSize` are
  already relaxed in `.rubocop.yml` (200, 250 and 25), with a stated rationale.**
  So crossing one is a real signal rather than a cop to placate, and the honest
  fix is to extract. This session crossed three: `ScopeWriter` at 224/200, which
  produced `ScopeCombinations` — a coherent unit, "the questions a set of exact
  triples can be asked", read-only; `WorkflowsControllerPatch` at 255/250, which
  came back under by moving `combinations_for` into that class and extracting
  `resolved_copy_source`; and `find_tracker_and_role` at 25.08/25, which split
  into itself and `find_role`. Raising a Max, or adding a `.rubocop_todo.yml`
  entry, would have been weakening the gate. Note that the length cops count
  **code** lines only, so the long explanatory comments this repository favours
  are free — and that 25.08 against a limit of 25 is what an extra local variable
  costs, so the margin is thinner than it looks.
- **A new locale key has to exist before the example that asserts it can mean
  anything.** An `expect(flash[:warning]).to eq(I18n.t(:some_new_key))` on the
  old code fails with
  `expected: "Translation missing: en.some_new_key" got: nil` — which *is* a
  valid red (the `nil` is the defect), but only because the right-hand side is
  the thing that is missing. Read which half of such a failure is the finding.
- **Redmine's fixture `roles_005` is *Anonymous* and `roles_004` is *Non
  member*; `roles_003` is *Reporter*, an ordinary role with no member in
  `projects_001`.** `Role.anonymous.consider_workflow?` is false in the
  fixtures and `Role.non_member`'s is true, so a spec about "a role with no
  member" and a spec about "a builtin role that takes part in a workflow" need
  different fixtures.
- **`Role#<=>` sorts by `(builtin, position)`, which is exactly what
  `Role.sorted` orders by.** So `(a + b).uniq.sort` over two `Role.sorted`
  relations is deterministic and matches the scope, on every database — which is
  what `ProjectOptions.visible_roles` relies on rather than re-querying.
- **A `Struct` returned from a service changes every `eq` that asserted the old
  value, and the failure is legible: `expected: 1 got: #<struct ... written=0,
  skipped=1>`.** Five such examples had to move; none was weakened, and saying
  so explicitly in the session report is part of the change, because "I updated
  the tests" and "I weakened the tests" look identical in a diff stat.
- **An empty `<% if %>` branch in ERB passes RuboCop and reads as a mistake.**
  When a new condition means "render nothing here", reorder the branches so the
  empty case is the absent `else` rather than an empty `then`.
- **A partial local that arrives as `nil` is not the same as one that was not
  passed.** `defined?(offered)` is true for a local passed as `nil`, so
  `offered = true unless defined?(offered)` leaves it `nil` — and a `nil` that
  gates a button removes the button silently. Treat both: `if !defined?(x) ||
  x.nil?`.
- **A query count measured inside the counted block can include a fixture
  load.** The first probe of the settings tab read 8 queries and one of them was
  `SELECT "projects".* WHERE id = $1`, which is `projects(:projects_001)` loading
  lazily. Reference every fixture the example needs *before* subscribing. (This
  is the same trap as the memoised-`let` entry further down, met from the other
  direction.)

Everything from here down is carried forward from earlier sessions.

- **A migration reversibility check needs a database built from *core*
  migrations only, and a host that has run the suite has neither.** The suite's
  `maintain_test_schema` dumps `db/schema.rb` **including** the plugin's table
  and column, and `rake db:drop db:create db:migrate` then loads that dump — so
  the plugin's structures are back with no migration bookkeeping behind them,
  `VERSION=0` prints nothing at all, and the check silently proves nothing.
  Redmine does not track `db/schema.rb`, so there is nothing to `git checkout`:
  **delete** it, then `db:drop db:create db:migrate`, then the plugin migrate,
  and only then `VERSION=0`. Redmine records plugin versions in
  `schema_migrations` as `<n>-<plugin_id>` rows, so
  `select version from schema_migrations where version like '%-%'` coming back
  empty is the symptom to check for. CI avoids all of this by running the check
  **before** the suite, on a host built minutes earlier.
- **`bundle exec rubocop` says "command not found: rubocop" even after a clean
  `bundle install`.** Bundler 4 in this container does not put the gem's
  executable on the path. The gem is installed and works — call its `exe/`
  script directly, as in the block above. Ten minutes went into re-running
  `bundle install` and reading its output for an error that was not there.
- **A backgrounded command reports "completed" while it is still running.** The
  harness watches the shell that `nohup … &` returns from, not the process. Both
  a `dev/setup.sh` and a suite run were read as finished on the strength of that
  notification, and the log was mid-`bundle install` in one case and mid-suite in
  the other. Wait for the log to say so — `until grep -q 'examples,' <log>; do
  sleep 5; done` — and never quote a result the log has not printed.
- **A concurrency test needs the fixtures to be *committed*.** The suite runs
  each example inside a transaction, so a second connection sees none of what the
  example arranged. `self.use_transactional_tests = false` for that group, and
  clean up in an `after` hook, because nothing else will.
- **`git stash push -- lib/` is safe only while the fix is uncommitted.** Once
  it is committed the stash has nothing to save, exits 0, says so quietly, and
  the "old code" run is the new code passing itself. Committed fix →
  `git show <old-sha>:<path> > <path>`, run, `git checkout -- <path>`.
- **The Bash working directory persists between calls, and `cd .redmine/<host>`
  makes `git` answer for Redmine's checkout.** A `git stash push` typed from
  there stashes nothing and says "No local changes to save", which reads like the
  plugin's tree being clean. Prefix with
  `cd /home/user/redmine_project_workflows &&`.

- **A cell of a matrix is not the unit a delete may key on.** Three controls
  over two rows, each of which can independently be left at "no change": the key
  is (cell, rule group), and the two flags inside the shared row need finer
  handling still. Whenever a screen submits several controls under one key, ask
  which of them the delete is allowed to speak for.
- **A grid that renders what the selection *stores* lies about what applies.**
  The administration matrix shows a project's own rules, so a project that
  inherits renders as an empty grid — which reads as "nothing is permitted" and
  is the opposite of the truth. The panel above it is the only thing that can say
  so, and it has to, because the grid is the part people read.
- **`git checkout -- .` after a red-on-old-code run restores to HEAD.** Which is
  right *only if the fix is committed first*. Commit, then `git show <old>:<path>
  > <path>`, run, then `git checkout -- .`. Carried over from last session and
  used correctly this time; keeping it here because it is the trap most likely to
  destroy work.
- **PostgreSQL and MariaDB both stop when the container is idle.** `pg_isready`
  and `mariadb -e 'SELECT VERSION()'` before blaming a spec: a dead server shows
  up as `ConnectionNotEstablished` in a `before(:suite)` hook, which reads like a
  broken spec_helper.
- **`Array#sort` raises on booleans.** `pluck(:author, :assignee).sort` is
  `comparison of Array with Array failed`, because `false <=> true` is nil. Sort
  by a mapped key.
- **Proving an example red on the old code: stash the one file, not the tree.**
  `git stash push lib/…/the_one_file.rb`, run the suite, `git stash pop`. What
  makes this go wrong is stashing too much: a new locale key has to **stay** in
  the working tree, or `I18n.t` returns the "translation missing" string and the
  example fails for a reason that has nothing to do with the code under test —
  which reads as proof and is not. And once the change is **committed**,
  `git stash push` on that file has nothing to stash: it exits 0, says "No local
  changes to save", and the "old code" run is the new code passing itself. Use
  Commit the change, then use `git show <old-sha>:<path> > <path>` …
  `git checkout -- <path>` instead. This session was fooled by the stash form
  once, and then by the replacement form once — see the next entry, which is why
  "commit first" is part of the recipe rather than an aside.
- **…and `git checkout -- <path>` afterwards restores it to `HEAD`, which throws
  an *uncommitted* fix away.** The mirror image of the trap above, and it cost
  an earlier session the C01 view fix once: writing the old version over the file,
  running, then `git checkout --` left the old version in place, because `HEAD`
  did not yet carry the new one. `git status` then shows the spec file modified
  and the fix silently gone. **Commit the fix first**, then restore from the
  previous commit — that way `git checkout --` puts the fix back rather than
  removing it.
- **A backgrounded `dev/setup.sh` reports success immediately and means
  nothing.** `nohup dev/setup.sh … &` returns at once, so the shell's exit code
  describes the `&`, not the setup. Read the log file. Both real failures were
  late and quiet: a missing `rsync` (from `dev/sync.sh`, one line) and a missing
  `libpq-dev` (from the `pg` gem build, buried in bundler output). The apt line in
  "Development environment" below installs both — run it *first*.

- **A Deface anchor inside an `<% if %>` renders nothing in the `else` branch,
  and nothing says so.** Core's `issues/_attributes` draws the status control two
  ways, and the second — a plain label — is what `@allowed_statuses.present?`
  being false produces. Anchor on the *branch you need*, both of them if the
  feature has to survive both, and write the assertion so that it can only pass
  in the branch it is about. Read the whole surrounding conditional before
  choosing an anchor.
- **`new_statuses_allowed_to` returns `[]`, not `[current_status]`, when the
  workflow permits nothing.** `statuses << initial_status unless statuses.empty?`
  — the initial status is appended only when something else was found. So an own
  empty workflow, *and* any dead-end status on a stock installation, removes the
  status select from the form entirely rather than emptying it.
- **A query object that takes a parameter it does not use for everything is a
  contract waiting to be broken.** WP8's map took a `tracker:` for its edge query
  and read the status and the dropdown off the issue. Consistent only because one
  caller reconciled them first. If two inputs must agree, take one.
- **`position_of`-style helpers that answer on nil conflate two nils.** A missing
  record can be core's `old_status_id = 0` pseudo-status *or* a row naming a
  deleted status. Tell them apart by the id, not by the record being absent.
- **`Role.anonymous.consider_workflow?` is false; `Role.non_member`'s is true.**
  So "a reader with no workflow role" is an anonymous visitor, not a non-member —
  a non-member of a public project gets *Non member*, which does take part.
- **A `first_or_create!` on `Member` finds the fixture's member and ignores your
  roles.** `users_003` is already a member of `projects_001` as *Developer*. Read
  the fixture, or arrange against the role the user actually holds.
- **`Group.generate!` is a Redmine test helper, not available under RSpec**, and
  a group cannot hold an issue unless `Setting.issue_group_assignment` is on —
  which is cached on the class, so an example that sets it must clear the cache
  again.
- **`WorkflowTransition` validates its status associations**, so a row naming a
  nonexistent status cannot be created through the model. Create it against a
  real status and `delete_all` the status afterwards.
- **A route helper's output is HTML-escaped in the page.** `expect(body).to
  include(some_path)` fails on any path with two query parameters, because `&`
  renders as `&amp;`. Wrap the expectation in `ERB::Util.html_escape`.
- **`rspec` and `rubocop` are not on the PATH until their bundle is installed in
  this container**, and `bundle exec rspec` from the wrong directory reports
  "command not found: rspec" rather than a path error — which reads like a broken
  gem and is a wrong `cwd`.
- **`rm -f some/spec.rb` from the wrong directory silently removes nothing.** Two
  throwaway probe specs survived into a suite run and a RuboCop run that way, and
  the only symptom was a file count one higher than expected (92 rather than 91)
  and an example count one higher. If a number is off by one, look for a probe.

Everything from here down is carried forward from earlier sessions.

- **A new controller action is 403 for everybody until `init.rb` names it in a
  permission.** Administrators included, and the symptom is a forbidden page
  rather than an "unmapped action" error anywhere. `spec/plugin_conventions_spec.rb`
  now asserts structurally that every action of `ProjectWorkflowsController` is
  named by at least one of the two permissions.
- **`to_h` over an unordered `pluck` is a cross-database divergence waiting to
  happen.** Where two rows can share a key, the last one wins — and which one that
  is differs between PostgreSQL and MySQL. Nine green CI cells hide it until a
  database in the field has such a pair. Keep both, or sort before picking.
- **An unscoped `include(user.name)` on a settings page proves nothing.** Core
  renders the Members tab into the same response, so the name is there whatever
  the thing under test says. Scope the assertion with `css_select`.
- **A project whose module is disabled, or which is archived, gives 403 — not
  404.** `authorize` → `Project#allows_to?` → `deny_access` → `render_403`. Only a
  finder that cannot match its parameter gives 404.
- **`Set#flatten` flattens nested Sets, not the Arrays inside one.**
  `Set[[1, 2]].flatten` is still a Set of one Array, so a `reject(&:zero?)` after
  it raises `NoMethodError` on `Array`.
- **A query-count example can measure lazy fixture loading.** A memoised
  `let(:trackers_list) { [trackers(:x), trackers(:y)] }` referenced for the first
  time *inside* the counted block adds two SELECTs to the first iteration and none
  to the second — which looks exactly like an N+1 and is not. Force the lists
  before counting.
- **A JavaScript scenario inherits the previous one's state.** The undo stack
  lives for the life of a page, so `dev/check-bulk-js.mjs` re-evaluates the whole
  `javascript_tag` block per scenario. The first version of those checks passed
  vacuously on a stack an earlier scenario had left behind.
- **`say_with_time` prints a row count only if its block returns an Integer.**
  `execute` returns an adapter result object, so a migration that wraps a raw
  `INSERT ... SELECT` prints the elapsed time and nothing else. A README that
  promises the operator a number has to be checked against the migration.
- **Redmine's plugin migration task defaults to *development*.** It is
  `=> :environment`, so `rake redmine:plugins:migrate` with no `RAILS_ENV`
  migrates the wrong database and prints output that looks like success. Every
  migrate command in user-facing documentation needs `RAILS_ENV=production`, and
  CI cannot catch its absence because CI sets `RAILS_ENV: test` job-wide.
- **Migrations reverse in the order they were applied.** `VERSION=0` runs 005's
  down, then 004's, and so on — so `project_workflow_scopes` is dropped *before*
  migration 001 deletes the project rules. Do not describe a down sequence from
  reading one migration.
- **A documented query count is worth measuring, not estimating.** `docs/design.md`
  said the settings tab costs four collection queries; it is six. The
  constant-cost property was right and the number was not — so state the property
  and measure the number.
- **Redmine core already has an issue-form status help icon and modal.** Do not
  build a second one. `issues/_attributes.html.erb`,
  `label_open_issue_statuses_description`,
  `showModal('issue_statuses_description')` and
  `issues/_issue_status_description` — byte-identical in 5.1, 6.1 and 7.0 apart
  from `sprite_icon` arriving at 6.0. `IssueStatus#description` is a real core
  column on all three.
- **A `rubocop -a` autocorrect can *create* the offence you then grandfather.**
  `Layout/MultilineOperationIndentation` re-aligned a 101-character line in core's
  copied body to 125, and the todo entry written straight afterwards explained it
  away as "keeping core's shape" — the exact opposite of what had happened. Read
  what an autocorrect did before annotating what it left.
- **Redmine 6.1 emits a `to_time` deprecation warning from its own `time_tag`**
  whenever `@project` is set, via `User#time_to_date`. WP6's audit line is the
  first thing in the plugin to call `authoring`, so the warning now appears once
  in the 6.1 suite output. It is core's, not the plugin's; core hits the same path
  on `repositories/_changeset`. Do not chase it.
- **`rubocop -a` over a grandfathered codebase is a 244-offence diff through the
  writers and the query services.** Safe cops only, and run the whole suite
  afterwards on more than one version before believing it. Then regenerate the
  todo and *annotate* it: a generated list cannot tell debt from a decision.
- **`git checkout -- .` in a scratch script destroys uncommitted work.** It
  restores to **HEAD**, not to what you had. **Commit first, then run revert
  experiments** against the commit, and never let such a script touch anything
  but the file it reverted.
- **Deface renames an attribute whose value contains ERB.**
  `style="width:<%= ... %>"` is matched as `td[data-erb-style]`, not `td[style]`.
  A selector that does not match produces no error and no output.
- **A `<select>` that acts on its own `change` event is an accessibility trap.**
  Arrow keys on a closed select fire `change` per step, so a keyboard user applies
  every value on the way to the one they wanted. This is why the row and column
  actions, and the undo, are links.
- **Redmine's administration screens are behind sudo mode, in the suite too.** A
  spec that logs in as administrator gets the password form instead of the page
  unless it also sets `@request.session[:sudo_timestamp] = Time.now.to_i`.
- **`Setting.plugin_<id>` is cached on the class.** A spec that writes it needs
  `after { Setting.clear_cache }`.
- **`dev/sync.sh` deletes what it did not copy.** A throwaway spec written
  directly into the host's `plugins/` directory is gone after the next sync.
- **`dev/run.sh` runs the whole spec directory even when given one file.** To run
  one file, call `bundle exec rspec plugins/redmine_project_workflows/spec/<path>`
  inside the host after `dev/sync.sh`.
- **The Bash working directory persists between calls — sometimes.** A `cd` into
  `.redmine/<host>` for one command leaves the next one there, and `git` then
  answers for Redmine's checkout rather than the plugin's, and `dev/run.sh` is not
  on the path. Prefix with an explicit
  `cd /home/user/redmine_project_workflows &&`.
- **Redmine's stylesheet removes the focus outline only on form controls and on
  `button.tab-left`/`button.tab-right`** — never on `a`, on 5.1, 6.1 or 7.0.
- **The plugin ships no stylesheet.** A class on a plugin element is a hook for a
  theme, not colour — so the words have to carry the whole meaning, and markup
  structure (a block element) is the only way to stop items crowding onto one
  line.
- **`Array(relation).size` copies the records; `relation.size` does not.**
- **Never extend `project_settings_tabs` with `ProjectsHelper.prepend`.** A
  neighbouring plugin's alias chain resolves through `ProjectsHelper.ancestors`,
  copies the prepended method, and loses its `super` — core's own tabs vanish and
  every settings page raises `NoMethodError`. `ProjectsController.helper(Mod)`
  instead: beside `ProjectsHelper`, never inside it.
- **Redmine renders every settings tab's partial on every visit.** `showTab` only
  hides and shows what is already in the page, so a tab's content has to be cheap.
- **`ProjectsController#update` calls the `settings` *method* and then renders the
  settings view**, so a `before_action` would not run on that path. A helper
  sidesteps the question.
- **A tab entry's `:action` may be an action hash, not only a permission name.**
  That is how a tab is made visible to holders of *either* of two permissions.
- **A Redmine path helper uses `Project#to_param`, which is the identifier** —
  except in a form built with `form_tag({}, method: :get)`, which reuses the
  request's own path parameters and carries the **id**. Both appear in one page,
  so use the route helper in the expectation.
- **A spec can be passing on another spec file's fixtures.** `spec/models/` and
  `spec/services/` specs that create an `Issue` need `:enumerations`;
  `project_statuses_spec.rb` needs `:projects_trackers`.
- **A reused test database hides a missing fixture.** Two hosts disagreeing is a
  signal, not a flake.
- **Rails' `include_all_helpers` does not reach a plugin's `app/helpers`.** Name
  it with `helper MyHelper`; for a view rendered by a *core* controller, do it from
  the patch's `self.prepended(base)`.
- **A module mixed into a controller must not have public methods.** Every public
  instance method of a controller is an action.
- **Redmine 5.1's `MenuManager::Mapper#push` is not idempotent.** Guard with
  `Redmine::MenuManager.map(:admin_menu).exists?(...)`.
- **`dev/setup.sh` does not drop the test database.** Deleting `.redmine` is not
  the same as starting clean.
- **A CI run marked "cancelled" is usually the concurrency group, not a failure.**
  Read the *head's* run.
- **`rails runner` without `RAILS_ENV=test` boots development and dies on a
  missing `listen` gem.** Every command against a host needs `RAILS_ENV=test` in
  the *same* invocation — shell exports do not survive between tool calls.
- **PostgreSQL rejects `ORDER BY` on a column that `SELECT DISTINCT` does not
  select.** `reorder(nil)` first.
- **`.or` must come before `.distinct`, not after.**
- **MariaDB 10.11 rejects a table alias in a single-table `DELETE`.** PostgreSQL
  and MySQL 8.4 both accept it, so a statement can pass six of nine CI cells.
- **`mariadb -e "…" | head` reports `head`'s exit status, not MariaDB's.**
- **MariaDB *can* be installed in this container** — `apt-get install -y
  mariadb-server libmariadb-dev`, then `mariadbd --user=mysql
  --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock` in the background, a
  `redmine` user with `GRANT ALL`, and `dev/setup.sh <branch> mysql <ruby>`.
- **A unique index cannot enforce a key with a nullable column** on any of the
  three supported databases.
- **A cache built from the rules is not invalidated by the scope writer.**
  `Resolver.reset_cache!` clears both request caches, but it has to be *called*.
- **InnoDB refuses to drop the last index with a foreign key's column leftmost**
  (MySQL error 1553). Migration 005 checks for its replacement first.
- **Rendering from a Redmine `before_action` answers before `require_admin`.**
  Core's `WorkflowsController` declares its finders before the authorization
  callback. Collect and let the action decide. `ProjectWorkflowsController` is the
  other way round on purpose — `authorize` is declared first, so *its* finder may
  render.
- **A migration's effect is invisible to the process that ran it.**
- **Neither half of the old timestamp trap was true**, and it is here as a
  correction because it stood in this list, in a migration comment and in
  `docs/DECISIONS.md` for a day. It used to read "PostgreSQL will not cast a text
  literal to a timestamp inside a `SELECT` list, so the backfill uses
  `CURRENT_TIMESTAMP`". Measured on PostgreSQL 16.13: a bare quoted literal in
  the `SELECT` list of an `INSERT … SELECT` **is** coerced to the target
  timestamp column, no cast needed. And `CURRENT_TIMESTAMP` is UTC only on
  PostgreSQL — `AbstractMysqlAdapter#configure_connection` sets `sql_auto_is_null`,
  `wait_timeout` and `sql_mode` and **no** `time_zone`, in Rails 6.1, 7.2 and 8.0
  alike, so on MySQL and MariaDB it returns the server's local time and Rails
  reads it back as if it were UTC. Build the timestamp in Ruby:
  `connection.quoted_date`, wrapped in the standard `TIMESTAMP '...'` type
  keyword, which all three accept (finding F09).
- **A spec that fails while creating a project poisons the database.** To clear:
  `DELETE FROM projects_trackers WHERE project_id NOT IN (SELECT id FROM projects)`
  — without a table alias, or MariaDB refuses.
- **A new project already has `Setting.default_projects_modules` enabled.** Guard
  with `module_enabled?`.
- **`Project#archive!` is private; `Project#archive` is not.**
- **Redmine's I18n applies only the `one`/`other` plural forms to Polish.**
- **A YAML value containing `": "` needs quoting.** `spec/locales_spec.rb` catches
  it, on every host.
- **`Rails.application.config.to_prepare` in `init.rb` never runs.** Call
  `apply_patches` in the body of `init.rb` instead.
- **A plugin's permissions accumulate on every code reload in development.**
  Harmless, and true of every Redmine plugin.
- **Never let `spec/spec_helper.rb` apply the patches itself.**
- **Redmine 7.0 has no `request_store`.** Use `RedmineProjectWorkflows::Current`,
  and reset it in specs.
- **The plugin is copied into the Redmine host, not symlinked.**
- **Run the migration checks before the suite.** `maintain_test_schema` reloads
  `db/schema.rb` when the suite starts and wipes the plugin's migration
  bookkeeping, after which `VERSION=0` silently does nothing.
- **`render_404` does not abort the action.** It renders and returns `false`. In a
  `before_action` the *chain* does halt, so one `render_404` as the last statement
  of a callback is safe; two are not.
- **`User#roles_for_project` caches memberships on the object.**
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.**
- **`Naming/MemoizedInstanceVariableName` fires on a method whose body ends in
  `@other ||= ...`** — and on `find_statuses`, where `@statuses` is the name the
  view reads, so the cop's own fix would empty the matrix.
- **`.contextual` is floated, so it has to come *before* the heading.**
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** What changed at 6.0
  is that CSS icons became SVG sprites — five things the plugin renders go through
  `RedmineProjectWorkflows::VersionHelper`. `app/helpers/workflows_helper.rb` and
  `app/views/workflows/_form.html.erb` are byte-identical between 6.1 and 7.0 and
  differ from 5.1 only in how the toggle link is written;
  `issues/_attributes.html.erb` differs only in `sprite_icon`.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`.
- **`safe_attributes=` sets `project_id` before `tracker_id`**, on purpose. This
  is why finding G03 is not a two-line fix.
- **Rails casts oddly in `where(id:)`.** `Project.where(id: ['1e5'])` returns
  project 1. Check the *shape* of an id (`/\A\d+\z/`) before querying, or
  intersect against an already-loaded list.
- **A workflow rule can make an issue invalid.** A generic `due_date required`
  rule makes `Issue.create!` fail in a spec that arranges the rule first.
- **`rails-ujs` is loaded on all three versions**, so `link_to ..., method: :post,
  data: { confirm: ... }` works. The row and column actions and the undo do not
  depend on it — they are `link_to_function` with an `onclick`.

### Traps from the 2026-08-28 audit session (building a host with no `apt`)

- **The `pg` gem cannot be built in a stock Claude Code web container.**
  `libpq-fe.h` is absent, there is no `apt-get`, and `pg` 1.5's `have_library`
  probe additionally fails on a modern GCC even when headers are supplied by
  hand. A PostgreSQL *server* is present and startable
  (`service postgresql start`), which is useful for testing SQL directly through
  `psql` — that is how "PostgreSQL parses 1,000 nested `OR`s fine" was measured
  — but the Rails adapter cannot be installed.
- **The whole suite runs on SQLite**, and this is the useful fallback: **861
  examples, 0 failures, 9 pending**. Exactly one thing blocks it, and it is a
  real defect rather than a test-environment quirk — the three
  `TIMESTAMP '<literal>'` sites in migration 004, `ScopeCopier` and
  `ProjectWorkflowCopier`. SQLite has no `TIMESTAMP` keyword, so `rake
  redmine:plugins:migrate` aborts inside 004 with `no such column: TIMESTAMP`
  and leaves migrations 001–003 applied. See `2026-08-28-claude-audit.md` F02.
- **`rsync` is not installed**, so `dev/sync.sh` fails at its only command. A
  six-line shell shim over `tar` is enough; `dev/setup.sh` otherwise works.
- **`CoreMethodDigest` runs outside RSpec.** `rails runner` gives all nineteen
  digests in 34.5 ms. Worth knowing before designing anything around it — it is
  what ADR-002's runtime drift check is built on, and it also reveals what the
  gate does *not* cover: the three singleton-class shadows, of which
  `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions` are the two INV-1 rests on.

### Traps from building ADR-004

- **MySQL and MariaDB run REPEATABLE READ; PostgreSQL runs READ COMMITTED.** Any
  "wait for the other transaction, then look again" pattern is broken on the
  MySQL family unless the second look is a **locking** read (a *current* read) or
  a new transaction. Two defects here came from exactly that, both green on
  PostgreSQL for months. When a concurrency example passes on PostgreSQL, run it
  on MariaDB before believing it.
- **An EXISTS in front of a delete is a check-then-act.** It is safe only where
  the caller can prove nothing else is writing. Folded into `delete_rules` it
  broke *return to the generic workflow*, which deletes rules a matrix save may
  be writing at that moment — caught on MariaDB, where the interleaving happens.
- **A concurrency example that passes with the lock disabled is not a test.** The
  first draft here paused *inside* the read it meant to protect, so both paths
  gave the same answer. The pause belongs **after** the read and before the
  write. Disable the lock and watch it go red before trusting it.
- **`Metrics/ClassLength` is a signal, not a cop to placate** — the seventh
  extraction in this repository (`ScopeBulkWriter`) and, like the six before it,
  a genuine improvement: it is now the one place a write to these tables is
  expressed as a set operation.

### Traps from the 2026-08-29 measurement of *give own workflow*

- **One scenario per process, or the numbers are fiction.** A probe that ran
  every scenario inside one transaction had the later ones measuring the
  accumulated undo of the earlier ones. On MariaDB that turned a 0.05 ms delete
  into 4.2 s and pointed at an innocent piece of code. `measure_clean.rb` in the
  scratchpad takes MODE/COMBOS/RULES from the environment and does exactly one.
- **`$stdout.sync = true` in any probe that runs for minutes**, or a run killed
  half way leaves an empty log and no idea how far it got.
- **Killing a rails runner mid-transaction leaves MariaDB rolling back**, and the
  next run fails with `Lock wait timeout exceeded` for a minute or two. Wait, or
  check `information_schema.innodb_trx`, rather than assuming the probe is wrong.
- **The same measurement can vary 2.7× between runs** on the per-row path (110 s
  and 294 s for the same 20,000 combinations on PostgreSQL), because it holds a
  transaction open for minutes. Take two samples of anything that slow before
  quoting it.

### Traps from the 2026-08-29 WP14 session

- **The Bash tool's working directory persists between calls, and a `cd` into a
  host checkout survives into the next command.** It cost two mistakes here: a
  `python3` edit that wrote nothing because the relative path no longer resolved,
  and — worse — a `cp` that restored a plugin file into
  `.redmine/7.0-stable-postgresql/app/controllers/`, i.e. into **Redmine's own**
  `app/controllers`, where it would have defined the controller twice. Use
  absolute paths for every write, and check `git status` in the host checkout if
  a restore looks odd.
- **`spec/plugin_conventions_spec.rb` greps the sources for the exact phrase
  "INV-4's one deliberate exception" and fails if more than one file under
  `app/`, `lib/` or `db/` carries it.** A new comment that merely *refers* to the
  exception has to say so in other words — which is the gate working, not a
  nuisance: the phrase is the marker, and a second copy of it is a second method
  claiming the exemption.
- **`WorkflowTransition` validates the presence of `new_status`**, so a spec
  helper that builds a transition with `new_status_id: 0` raises. `old_status_id`
  0 is fine — that is core's "new issue" pseudo-status.
- **The drawing has one arrow that is not a rule.** Where nothing leaves the
  entry node, core's fallback to the tracker's default status is drawn as well,
  so `graph.edges.size` is one more than the rules a spec inserted. The ceiling
  counts arrows to place, not rules.
- **A settings partial should read the `settings` local, not `Setting`.** They
  differ on a page Redmine is re-rendering after a failed save.

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

WP0..WP15 are done and WP16 is three quarters done. "Carry on" means, in order:

0. **Read `docs/release-criteria.md` first.** It is the shortest statement of
   where the project actually is, and the last work package is measured against
   it rather than against a feeling.
1. **Check CI on the head.** Pushing a commit cancels the in-flight run for the
   previous one, so read the *latest* run and treat a cancelled earlier one as
   superseded rather than failed.
2. **WP16 item 1** — the upgrade rehearsal from a real previous release. *Exact
   next step* says what it needs and what it is blocked on (a tag, which is
   Jan's to authorise).
3. **Before any release, repeat the 45-plugin run.** It is still the only
   environment in which the permission-ownership gate can fail, and the
   diagnostics page is where that gate reports — so the run is also the way to
   see that page say something other than "in order". Since WP12 that page also
   checks the five Deface anchors against the host's own views, which on a
   45-plugin 5.1 is the first environment where a neighbour could plausibly have
   replaced one of them. It is release criterion A1.

Do not invent a work package on top of WP16. Do not re-open the 2026-08-27 run's
"Checked and not filed" table: 24 claims, thirteen rejected or already decided,
four of them by Jan with an explicit instruction not to re-open them. Do not
shorten the `_rules` suffix off either permission name. Do not remove the alpha
warning without Jan — criterion A3 is his to answer and no CI run substitutes for
it. And do not hand-edit a digest in
`lib/redmine_project_workflows/compatibility.yml` — read what changed first, then
measure with `dev/measure_compatibility.rb`; updating a digest ahead of reading
the diff is the one thing that makes the whole gate useless.
