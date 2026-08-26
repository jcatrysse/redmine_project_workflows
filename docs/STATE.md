# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0, WP1, WP2 and WP3 are **done**. WP4 is next and has not
  been started. WP0..WP7 are specified in `docs/implementation-plan.md`.
- **What exists:** the plugin as shipped in 0.0.3, the WP0 repairs, the scope
  model from WP1, the core seams from WP2, and — as of this session — a workflow
  summary page that counts the workflow you selected instead of mixing every
  project's rules into the generic totals, plus a new **inventory** screen that
  answers which projects have taken a workflow over.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/docs-review-xn2750`, which the environment had prescribed; nothing was
  committed there.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** none.
- **Open findings:** 4. `claude` F06 (row and column bulk actions skip mixed
  cells, WP5), `external` F11 (the README understates the operational risks,
  WP7), G02 (a cross-project bulk tracker change is an N+1, WP6) and G03
  (`Issue#project=` does not re-check the status against the new project, WP4).
  One more is marked wont-fix (G04). `claude` F01 — the summary page — was the
  fifth and is now fixed.
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` lists them, plus
  one line from `TEMPLATE.md` that is not a finding.
- **`spec/characterization/`:** **gone.** Its last example was `claude` F01, and
  WP3 inverted it; it now lives in `spec/controllers/workflows_controller_spec.rb`
  stating the repaired behaviour. The convention still stands and is written
  down in `dev/README.md`: a defect that is found but not yet fixed is pinned
  there first.

## What this session produced

**The summary page counts the workflow you selected** (`claude` F01, INV-4).
Core's `/workflows` page groups every row of the `workflows` table by tracker
and role with no `project_id` predicate at all, so as soon as one project took
a tracker over, its rules were added into the generic totals — the page told an
administrator the generic workflow had rules it does not have, and the red zero
that says "this workflow is unconfigured" stopped being reliable. `#index` is
now the plugin's, with an explicit predicate for the selection, and a project
selector above the grid says which workflow is being counted. Core's own body is
rewritten rather than called through `super` and corrected afterwards, because
`super`'s query *is* the defect: running it and throwing the answer away would
still be a workflow query with no `project_id` predicate.

**The count links carry the selection.** Core builds each cell's link with a
bare `{:action => 'edit', :role_id => ..., :tracker_id => ...}`, so a filtered
page would have shown one workflow's numbers and opened another's matrix. The
cell is the plugin's markup now — which meant reproducing core's own two shapes,
because 5.1 renders an `icon-not-ok` span instead of a zero while 6.0 and later
keep the number and colour it. Both live behind
`RedmineProjectWorkflows::VersionHelper`. With no project selected the URL stays
byte-identical to core's, so an administrator who does not use the plugin sees
the page they have always seen.

**The inventory** is a screen of the plugin's own at
`/project_workflow_inventories`, reached from the link next to core's *Summary*
button and from the summary page itself. One row per (project, tracker, role), a
column per rule type, the state as a **text** label — *Own workflow*, *Own empty
workflow*, *Inherits the generic workflow* — and every cell links into the matrix
it describes, pre-filled with that project, tracker and role. It filters on
project, tracker, role and rule type, and defaults to showing only the
combinations that have decided something.

Two things about it are worth knowing:

1. **The number is the project's own rule count, never the generic one.** An
   inheriting row therefore reads `0`, and the label next to it — not the number
   — is what says the generic workflow applies. The alternative, showing the
   generic count on an inheriting row, would have put a number in the cell that
   does not match the matrix the cell opens.
2. **"Show everything" does not build the product.** Projects × trackers × roles
   can be six figures on a large installation, and a page shows twenty-five of
   them. `Services::InventoryQuery` computes `total` by multiplication and
   addresses a page arithmetically, so a page costs the same whatever the
   installation's size, and is at most four queries however many rows it holds.

**A filter that survives nothing lists nothing.** "No filter" and "a filter was
given and nothing in it exists" have to be different answers: treating them the
same would answer a stale bookmark naming one deleted project with *every*
project. An unresolvable value is dropped, reported as a warning, and the rest
of the filter still applies — a filter is a form the operator can correct, so it
is not the 404 that the scope action links get.

**Three new Deface overrides, and the count went from eight to eleven** (INV-9).
The summary page's header is a **surround** rather than two inserts, because
Redmine floats `.contextual` and core always renders it before the heading while
the selector belongs under it; one anchor, one override, and Deface itself
raises if `<%= render_original %>` ever goes missing. Each of the three has an
assertion in `spec/integration/deface_overrides_spec.rb` that only it can
satisfy, and removing them was checked rather than assumed. The count is updated
in `CLAUDE.md` and `docs/design.md`.

**A refactor the lint gate forced, and it was the right cut.**
`WorkflowsControllerPatch` went over RuboCop's module-length limit. The project
selection plumbing — which parameters name projects, what they resolve to, and
which project ids a query carries — moved into
`Patches::WorkflowsControllerProjectSelection`, leaving the patch as what it
says it is: a set of replaced core actions. Every method in the new module is
**private**, because it is mixed into a controller and a public instance method
there is an action.

**Deleting the last characterization example uncovered five specs that had been
passing for a reason they never stated.** That file was the only one loading the
`enumerations` fixture, and five specs that create an `Issue` were relying on it
being in the database from an earlier file. Removing it turned `Issue.create!`
into "Priority cannot be blank" on a freshly built 5.1 host — and *not* on the
7.0 host, whose database still had the rows from a previous run, which is
exactly how this kind of thing hides. All five now declare the fixture.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 286 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 286 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 286 examples, 0 failures |
| RuboCop | 69 files, no offences |
| `zeitwerk:check` | "All is good!" on 5.1, 6.1 and 7.0 |
| Migration reversibility up → 0 → up | clean on 5.1, 6.1 and 7.0, asserted by reading the schema back in a **separate process** after each step: after `VERSION=0` neither `project_workflow_scopes` nor `workflows.project_id` exists; after `up` both do. WP3 changes no migration |
| Backfill (`dev/check-backfill.sh`) | passes on 7.0 + PostgreSQL |
| Locale parity | all eight files carry all 34 keys, none missing and none extra; every file parses |
| Independent review | run in this context rather than a fresh one — see "Known traps" |
| New specs against the old code | see below |
| CI | **not yet run for WP3** — the commit is being pushed now |

**The "fails on the old code" checks, run rather than assumed.** Each was done
by putting one thing back and leaving the rest of WP3 in place:

| Reverted | Fails |
| --- | --- |
| `patches/workflows_controller_patch.rb` | 11 examples — the 5 new summary-page examples and all 6 summary Deface assertions |
| the three new override files | 5 examples — one per override, plus the icon-shape assertion |

The inventory itself is new code with no "old" to revert to; its 17 examples
cover authorization (anonymous, non-administrator, administrator), the three
states, both modes, every filter, an invalid filter value, a filter that
survives nothing, a page past the end, and the rendered page's links and empty
state. `spec/services/inventory_query_spec.rb` adds the paging arithmetic —
walking the product one row at a time has to produce the same sequence as taking
it in one slice — and a query-count assertion that a page of two rows costs the
same number of statements as a page of one.

## Exact next step

Start **WP4** from `docs/implementation-plan.md`: the project settings tab and
the two permissions. In outline:

1. `view_project_workflow` and `manage_project_workflow`, registered in
   `init.rb`, and a tab added by patching `ProjectsHelper#project_settings_tabs`
   — **not** a Deface override; `docs/design.md` says so.
2. The tab renders the project's effective workflow, narrowed to the trackers
   enabled in that project and the roles that actually have members there.
3. Every action authorizes against the project it acts on, and no request
   parameter may widen that (**INV-7**). `ProjectWorkflowScopesController` is
   administrator-only today; it gains a per-project path with
   `manage_project_workflow`, and the existing admin path must keep working.
4. The inventory grows a per-project entry point at the same time: it is
   administrator-only now, and the same rows for one project are what the tab
   shows. `Services::InventoryQuery` already answers that — pass a single
   project.
5. Finding G03 belongs to WP4: `Issue#project=` re-checks the *tracker* against
   the new project but never the *status*, so an issue moved into a project
   whose own workflow does not use its status lands somewhere it cannot leave.
   Core has the same asymmetry, so this is a behaviour change a user can see —
   read `docs/review/findings/2026-08-26-wp2-observations.md` before deciding,
   and expect it to be an "Open — for Jan" item rather than a silent default.

## Known traps

Everything below cost time at least once. The first six are new this session.

- **A spec can be passing on another spec file's fixtures.** `spec/models/`
  and `spec/services/` specs that create an `Issue` need `:enumerations` for the
  default priority, and five of them did not declare it — they were living off
  the characterization spec's declaration. Symptom: "Validation failed: Priority
  cannot be blank", and *only* on a freshly created database. Before believing a
  green suite, ask which file loaded the fixture you are relying on.
- **A reused test database hides a missing fixture.** The 7.0 host passed the
  same code that failed on the 5.1 host, because 7.0's database still held rows
  from an earlier run. Two hosts disagreeing is a signal, not a flake.
- **Rails' `include_all_helpers` does not reach a plugin's `app/helpers`.** It
  is built from the host application's helper paths only, so a plugin helper
  module has to be named in the controller with `helper MyHelper` even though
  Zeitwerk autoloads it perfectly well.
- **A module mixed into a controller must not have public methods.** Every
  public instance method of a controller is an action. The new
  `WorkflowsControllerProjectSelection` is private throughout for that reason.
- **Redmine 5.1's `MenuManager::Mapper#push` is not idempotent.** 6.1 and 7.0
  reject an existing item of the same name first; 5.1 does not, so a plugin that
  pushes a menu item from `init.rb` gets a duplicate on every code reload there.
  (WP3 ended up not adding a menu item — the link sits in core's workflow action
  menu — but the next thing that wants one has to guard with
  `Redmine::MenuManager.map(:admin_menu).exists?(...)`.)
- **`.contextual` is floated, so it has to come *before* the heading.** Core
  always renders it first. An `insert_after` on the title expression puts it
  beside whatever follows the heading instead. Deface's `surround` with
  `<%= render_original %>` places content on both sides in one override, and
  raises if the placeholder goes missing.
- **`dev/setup.sh` does not drop the test database.** It runs `db:create`, which
  is a no-op when the database is already there, so a rebuilt host inherits
  whatever the previous cycle left in its database — including orphaned
  `projects_trackers` rows. Deleting `.redmine` is not the same as starting
  clean.
- **A failing gate in this container is worth reproducing before believing it.**
- **`rails runner` without `RAILS_ENV=test` boots development and dies on a
  missing `listen` gem.** The error says nothing about the environment. Every
  command against a host needs `RAILS_ENV=test` in the *same* invocation — shell
  exports do not survive between tool calls, only the working directory does.
- **PostgreSQL rejects `ORDER BY` on a column that `SELECT DISTINCT` does not
  select.** Redmine's `rolled_up_trackers_base_scope` is `distinct.sorted`, so
  plucking two columns from it needs `reorder(nil)` first.
- **`.or` must come before `.distinct`, not after.**
- **MariaDB 10.11 rejects a table alias in a single-table `DELETE`.**
  PostgreSQL and MySQL 8.4 both accept it, so a statement can pass six of the
  nine CI cells and fail three.
- **`mariadb -e "…" | head` reports `head`'s exit status, not MariaDB's**, and
  MariaDB echoes a failing statement instead of raising visibly.
- **MariaDB *can* be installed in this container** — `apt-get install -y
  mariadb-server libmariadb-dev`, then `mariadbd --user=mysql
  --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock` in the background,
  a `redmine` user with `GRANT ALL`, and `dev/setup.sh <branch> mysql <ruby>`.
- **A unique index cannot enforce a key with a nullable column** on any of the
  three supported databases.
- **A cache built from the rules is not invalidated by the scope writer.**
  `Resolver.reset_cache!` clears both request caches, but it has to be *called*.
- **InnoDB refuses to drop the last index with a foreign key's column
  leftmost** (MySQL error 1553). Migration 005 checks for its replacement first.
- **Rendering from a Redmine `before_action` answers before `require_admin`.**
  Core declares its own finders before the authorization callback, so anything a
  plugin renders from one of them is returned to whoever asked. Collect and let
  the action decide.
- **A migration's effect is invisible to the process that ran it.**
  `connection.table_exists?` still answered `true` after `drop_table` in the same
  `rails runner`, so a check written in one process proves nothing.
- **PostgreSQL will not cast a text literal to a timestamp inside a `SELECT`
  list.** The backfill uses `CURRENT_TIMESTAMP`.
- **A spec that fails while creating a project poisons the database for later
  runs.** To clear it: `DELETE FROM projects_trackers WHERE project_id NOT IN
  (SELECT id FROM projects)` — without a table alias, or MariaDB refuses.
- **A new project already has `Setting.default_projects_modules` enabled.**
  Guard with `module_enabled?`.
- **`Project#archive!` is private; `Project#archive` is not.**
- **Redmine's I18n applies only the `one`/`other` plural forms to Polish.**
- **A YAML value containing `": "` needs quoting.** `ruby -ryaml -e
  'YAML.unsafe_load_file(ARGV[0])'` over `config/locales/*.yml` catches it.
- **The Bash tool's working directory persists between calls.** Prefix edits
  with an explicit `cd /home/user/redmine_project_workflows &&`. This bit again
  this session: a `cd` into a host's `config/locales` made the next relative
  path fail outright.
- **`dev/run.sh` always runs the whole spec directory.** A path argument has to
  be written relative to the *host* root, not the plugin root.
- **`Rails.application.config.to_prepare` in `init.rb` never runs.**
- **Never let `spec/spec_helper.rb` apply the patches itself.**
- **Redmine 7.0 has no `request_store`.** Use
  `RedmineProjectWorkflows::Current`, and reset it in specs.
- **The plugin is copied into the Redmine host, not symlinked.**
- **Run the migration checks before the suite.** `maintain_test_schema` reloads
  `db/schema.rb` when the suite starts and wipes the plugin's migration
  bookkeeping, after which `VERSION=0` silently does nothing. `dev/check-backfill.sh`
  re-migrates, so it restores the bookkeeping and a reversibility check straight
  after it is meaningful again.
- **`render_404` does not abort the action.** It renders and returns `false`.
- **`User#roles_for_project` caches memberships on the object.**
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.**
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** What changed at 6.0
  is that CSS icons became SVG sprites — which now covers three things the plugin
  renders: the multiselect toggle, the workflow summary's empty cell, and any
  icon link. All three go through `RedmineProjectWorkflows::VersionHelper`.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`.
- **`safe_attributes=` sets `project_id` before `tracker_id`**, on purpose.
- **Rails casts oddly in `where(id:)`.** `Project.where(id: ['1e5'])` returns
  project 1. Check the *shape* of an id (`/\A\d+\z/`) before querying, or —
  better, where the list is already loaded — intersect against the loaded list
  instead of querying at all, which is what the inventory's filters do.
- **A workflow rule can make an issue invalid.** A generic `due_date required`
  rule makes `Issue.create!` fail in a spec that arranges the rule first.
- **The independent review ran in this context, not a fresh one.** The execution
  environment for this session forbade spawning subagents, and `CLAUDE.md` asks
  for a fresh one "if a subagent mechanism is available". A self-review defends
  its own reasoning; treat WP3 as having had a weaker review pass than WP2, and
  the next review session should look at it first.

## Development environment (rebuild from scratch in a fresh session)

```bash
# packages the container does not have
apt-get update -qq && apt-get install -y rsync libpq-dev

# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (about four minutes each; run them in
# the background in parallel)
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/setup.sh 6.1-stable postgresql 3.3.6
dev/setup.sh 7.0-stable postgresql 3.3.6

# the migration gates, BEFORE the suite, per host. RAILS_ENV=test has to be in
# the same invocation.
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0)
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows)
dev/check-backfill.sh .redmine/7.0-stable-postgresql 3.3.6

# sync the working tree and run the suite
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-postgresql

# lint (rubocop's binaries are not on PATH by default in this container)
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle install
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant.

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```
