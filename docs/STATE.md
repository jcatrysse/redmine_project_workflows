# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0, WP1 and WP2 are **done**. WP3 is next and has not been
  started. WP0..WP7 are specified in `docs/implementation-plan.md`.
- **What exists:** the plugin as shipped in 0.0.3, the WP0 repairs, the scope
  model from WP1, and — as of this session — every seam where Redmine's own code
  reads the workflow table without knowing that projects exist. `docs/design.md`
  now lists all of them with what was done about each, including the ones
  deliberately left alone.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/docs-review-tj7zpb`, which the environment had prescribed; nothing was
  committed there.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** none. WP2's two were answered A on 2026-08-26 — leave core's
  "only used statuses" label alone, and no unique constraint on `workflows`
  (keep `project_id` nullable and repair with the rake task). Both were already
  the implemented default, so no code changed; they have moved up into
  `docs/DECISIONS.md` under "Decided (Jan)".
- **Open findings:** 5, plus one marked wont-fix. Three were already open and
  are scheduled outside WP2 —
  claude F01 (the summary page counts project rules as generic, WP3), claude F06
  (row and column bulk actions skip mixed cells, WP5) and external F11 (the
  README understates the operational risks, WP7). Three came out of this
  session, in `docs/review/findings/2026-08-26-wp2-observations.md`: G02 (a
  cross-project bulk tracker change is an N+1, WP6), G03 (`Issue#project=` does
  not re-check the status against the new project, WP4) and G04 (the "all
  projects" filter builds one OR branch per overriding project — the wont-fix,
  with the trade written into `docs/design.md`). G01 and G05 from the same file
  are fixed. `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` lists
  the five.
- **`spec/characterization/`:** one file, **one** example — the summary page's
  count. It belongs to WP3. The plan's WP2 said "done when this directory is
  empty"; that was wrong and has been corrected in place, because that last
  example is claude F01 and therefore WP3's.

## What this session produced

WP2 is "correctness at the core seams": the places where Redmine's own code
reads the `workflows` table with no idea that a project could have its own
workflow. Four of them were wrong.

**The status filter and the status report** (`Project#rolled_up_statuses`,
external F08). Two faults, one on top of the other. The plugin had added a role
filter that core does not have, so a project with no members answered with *no
statuses at all* — emptying the status filter in every issue list and the status
report, whether or not any project anywhere had its own workflow. Underneath
that, the method collected trackers from the whole project tree but resolved the
workflow against one project, so a subproject's own workflow was read as if it
belonged to its parent. `StatusListQuery` now works on (project, tracker)
**pairs**: every project in the tree is resolved against its own scope (INV-6)
and the answers are unioned, in a fixed two queries however large the tree.

**Changing an issue's tracker** (`Issue#tracker=`, claude F02). Core asks the
tracker whether it uses the issue's current status *anywhere* — a union across
every project — and silently resets the status to the new tracker's default when
the answer is no. It now asks the issue's own project's effective workflow.
`Tracker#issue_status_ids` itself is left as the global union on purpose, and a
spec pins that: narrowing it would take a status away from an issue in a project
that does use it. The same question's other call site, in
`new_statuses_allowed_to`, lost the role filter WP1 had given it — that call
decides whether an issue *keeps* its status across a tracker change, and a
status only another role's rules use is still the issue's status. With the
filter, a Resolved issue was quietly offered the new tracker's default instead.

**Duplicating a role or a tracker** (claude F03). Both go through
`WorkflowRule.copy`, which after this plugin sees the generic rules only, so a
role copied from one that has project overrides arrived without them — and even
the rows it did copy would have been invisible without a scope.
`WorkflowRule.copy_with_projects` now carries the project rules and
`ScopeWriter.copy_scopes` mirrors the source's decisions, an own *empty*
workflow included. It is deliberately **not** folded into `.copy_one`, because
the administration copy screen falls through to core's `.copy` when no project
is selected and "copy the generic workflow" must not quietly become "copy every
project's workflow too". A spec pins that too.

**The "only used statuses" checkbox** (`find_statuses`, external F04). It
filtered on the physically selected project ids, so for a project that inherits
it found no rows, `.presence` fell back to *every* status, and the filter
switched itself off in exactly the case where it was wanted. It now asks for the
effective workflow of the selection. The fallback to every status remains for a
selection whose workflow really is empty — that is the only way an administrator
can fill an empty matrix in, and it is what core does on a fresh installation.

**Two things came out differently from what the plan assumed.**

1. **external F06's suggested direction is not available.** A unique index on
   `workflows` would have to include `project_id` and `field_name`, and both are
   nullable — NULL project id is what "generic" means, NULL field name is what
   "transition" means. PostgreSQL, MySQL and MariaDB all treat NULLs in a unique
   index as *distinct*, so the index would constrain nothing for the generic
   rows, which are the majority. The gap is covered from the other side instead:
   idempotency specs hold both writers to "saving the same matrix twice is the
   same as saving it once", and
   `rake redmine_project_workflows:deduplicate_workflow_rules` repairs a
   database that already has duplicates. The residual race — two administrators
   saving at the same instant — stays open and is core's as well. The one option
   that would work (`project_id` NOT NULL with 0 for generic) is logged for Jan.
2. **Migration 005 drops indexes rather than adding one.** Two of the four
   indexes migrations 001 and 002 put on `workflows` can never be chosen over
   the other two: one has the same columns as another with role and tracker
   swapped, which decides nothing for equality predicates, and the other is a
   strict prefix. Every index is paid for on every insert, and a workflow save
   inserts a whole matrix.

**An information leak, found while building and then fixed.** Core declares
`find_trackers_roles_and_statuses_for_edit` *before* `require_admin`, and the
plugin's override of it called `render_404` for a project id that does not
resolve. Rendering from a `before_action` halts the chain, so `require_admin`
never ran: `/workflows/edit?project_id[]=99999999` answered 404 to an anonymous
visitor while an id that exists answered 302 to the login page, so project ids
could be enumerated without logging in. It was first recorded for WP4 (finding
G01); the review role argued the repair is a few lines, because every action
that reads the selector already runs after authorization, and it was right. The
callback now only collects the invalid ids and the five actions return on them.

**The independent review, run in a fresh context, found two more defects.** Both
are fixed:

1. **The request cache went stale after a rule-only write.** The cached status
   list is derived from the rules, but only the scope-creating paths reset it —
   so emptying a matrix, saving into a project that already had a scope, saving
   the generic matrix, either copy path and the duplicate sweep all left the old
   answer standing. Not reachable over HTTP today, because every writing action
   redirects, but wrong for anything scripted and wrong the moment WP4 renders
   after a write. The comment on `Current` stated a contract the code did not
   meet, which is how it survived.
2. **Copying a role or a tracker was O(trackers × projects) round trips** — 381
   statements for three trackers and thirty overriding projects, inside one
   transaction. The rule copy is now one `INSERT … SELECT` per (tracker, role)
   carrying `project_id` through unchanged, and the scope copy one per rule type
   with a `NOT EXISTS` guard. The scope copy moved into its own service,
   `Services::ScopeCopier`; between it and `ScopeWriter` they are still the only
   places that create or remove a scope.

The review also caught that **two of the eight Deface overrides shared one
assertion**: the selector and the hidden field both render `project_id[]`, so
`include('project_id[]')` could not tell them apart and either could have
stopped matching unnoticed — which is precisely what INV-9 exists to prevent.
Each override now has an assertion only it can satisfy, and the count was wrong
in two documents: `CLAUDE.md` said five, `docs/design.md` tabulated seven.

And it caught a **false claim in a comment**: the request cache's rationale said
core builds a fresh `Tracker` instance per issue on a bulk tracker change. It
does not — `IssuesController#bulk_edit` hands one instance to the whole
selection and core memoises on it, so core asks its equivalent question once for
any number of issues. The plugin asks it once per distinct project. That N+1 is
recorded as finding G02 rather than fixed: batching it needs an
`IssuesController` hook WP2 has no other reason to open, and the alternative
re-introduces the system-wide scope read external F07 was raised to remove.
`Issue#tracker=` queries only when the tracker actually changes, so this is not
the issue hot path.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 238 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 238 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 238 examples, 0 failures |
| CI, all nine cells + RuboCop | green on `775c956`, `5a5e0d3`, `c382b3f` and `9e2a530` (runs 12–15). Runs 16, 17 and 18 failed the backfill gate on the three **MariaDB** cells and passed the other six — one cause, the `DELETE` alias described below, present in all three commits. `3e50f84` fixes it; runs 19 and 20 were cancelled by `concurrency: cancel-in-progress` as later commits landed, and **run 21 on the branch head `de68531` is green on all nine cells plus RuboCop** |
| RuboCop | 61 files, no offences |
| Independent review | run in a fresh context on the WP2 diff; every finding either fixed or recorded with its reason |
| `zeitwerk:check` | "All is good!" on 5.1, 6.1 and 7.0 |
| Migration reversibility up → 0 → up | clean on 5.1, 6.1 and 7.0, on freshly built hosts, before any suite ran — and asserted to leave no plugin table, no `workflows.project_id` and no plugin index behind |
| Backfill (`dev/check-backfill.sh`) | passes on 5.1, 6.1 and 7.0 against PostgreSQL, and on 7.0 against MariaDB 10.11 |
| Plugin suite, 7.0-stable + **MariaDB 10.11** | 238 examples, 0 failures — the first local run against MariaDB in this project |
| Plugin suite, 5.1-stable + **MariaDB 10.11** | 238 examples, 0 failures, backfill gate green — Rails 6.1 on MariaDB, which is where the review's two "probable" concerns lived (the grouped `count` in the duplicate sweep, and boolean group keys) |
| Migration reversibility on MariaDB | up → 0 → up clean, and `VERSION=0` leaves no table, column or index behind on InnoDB too |
| `rake redmine_project_workflows:deduplicate_workflow_rules` | discovered by the plugin loader and runs on all three |
| New specs against the old code | see below |

**The "fails on the old code" checks, run rather than assumed.** Each was done
by putting one file back and leaving the rest of WP2 in place:

| Reverted | Fails |
| --- | --- |
| `patches/project_patch.rb` | 5 of the 6 new rolled-up-statuses examples |
| `patches/issue_patch.rb` | the 3 new examples that state the project-aware tracker change |
| the two new prepends in `lib/redmine_project_workflows.rb` | 4 of the 9 new copy examples |
| `patches/workflows_controller_patch.rb` | the 2 new used-statuses examples |
| the five files the review pass changed | 7 of its new examples — 4 cache invalidation, 3 authorization |

**MariaDB can be run locally after all, and it caught a real defect.** Earlier
sessions recorded that neither MySQL nor MariaDB could be installed in this
container. `apt-get install -y mariadb-server` worked this time, and
`dev/setup.sh 7.0-stable mysql 3.3.6` builds a host against it. Doing so
explained a CI failure that PostgreSQL and MySQL both missed — see below. MySQL
proper is still only covered by CI.

**A CI failure this session was a real defect, found on the one database no
local run covered.** The orphan sweep added to `dev/check-backfill.sh` used
`DELETE FROM projects_trackers pt WHERE NOT EXISTS (…)`. PostgreSQL accepts the
table alias and so does MySQL 8.4; **MariaDB 10.11 rejects it** in a
single-table DELETE, so all three MariaDB cells failed the backfill gate on
`3432efd` while the other six passed. Rewritten without the alias
(`WHERE project_id NOT IN (SELECT id FROM projects)`) and verified on both
MariaDB and PostgreSQL, including the poisoned-database case.

Worth recording *how* that went wrong: the aliased form was first tested with
`mariadb -e "DELETE …" | head -3`, which printed no error and returned 0 — but
the `0` was `head`'s exit status, not MariaDB's, and MariaDB echoes the failing
statement rather than raising visibly there. The conclusion "both forms work"
was drawn from that. Running the real script against a real host is what
actually settled it.

**One local gate failed once, and it was the environment rather than the code.**
`dev/check-backfill.sh` failed on 7.0 with "backfill produced []". The cause was
orphaned `projects_trackers` rows left in the reused test database by an earlier
run of the script that had died halfway: the `projects` sequence hands the same
id out again and the script's own `Project.create!` then dies on
`projects_trackers_unique`, which reads as a backfill defect. The script now
sweeps those orphans before it seeds. Verified both ways — with the sweep removed
a poisoned database fails, with it in place the script passes after the table is
deliberately poisoned with the next two ids it will use.

## Exact next step

Start **WP3** from `docs/implementation-plan.md`, and empty
`spec/characterization/` while doing it. In order:

1. `WorkflowsController#index` counts per scope instead of mixing populations,
   with a project selector above the existing grid, defaulting to the generic
   workflow so the page behaves as before for anyone who does not use the
   plugin (claude F01). This inverts the last characterization example and
   empties that directory.
2. The inventory view: one row per (project, tracker, role), columns for
   transitions and field permissions, counts, and the state as a **text** label
   — *Own workflow*, *Inherits generic*, *Own empty workflow* — with colour only
   supporting the text. `Services::ScopeState` already answers that question for
   the matrix panel; check whether it can answer it in bulk before writing a
   second query for it.
3. Filters on project, tracker, role and rule type, plus "deviations only"
   versus everything, defaulting to deviations only.
4. An empty state with a sentence and two actions rather than an empty table.
5. Rows link into the existing matrices, pre-filled.

A new screen means new Deface anchors or a new route. If it is a route of its
own, follow WP1's precedent (`/project_workflow_scopes`): plugin routes are
drawn after core's, so a path under `/workflows` can shadow one. Any new anchor
needs its assertion in `spec/integration/deface_overrides_spec.rb` in the same
commit (INV-9).

## Known traps

Everything below cost time at least once. The first six are new this session.

- **`dev/setup.sh` does not drop the test database.** It runs `db:create`, which
  is a no-op when the database is already there, so a rebuilt host inherits
  whatever the previous cycle left in its database — including the orphaned
  `projects_trackers` rows described above. Deleting `.redmine` is not the same
  as starting clean.
- **A failing gate in this container is worth reproducing before believing it.**
  The one red gate this session was a poisoned database, not a defect, and one
  re-run after a cleanup established that.
- **`rails runner` without `RAILS_ENV=test` boots development and dies on a
  missing `listen` gem.** The error (`listen is not part of the bundle`) says
  nothing about the environment, so it reads as a broken host. Every command
  against a host needs `RAILS_ENV=test` in the *same* invocation — shell exports
  do not survive between tool calls, only the working directory does.
- **PostgreSQL rejects `ORDER BY` on a column that `SELECT DISTINCT` does not
  select.** Redmine's `rolled_up_trackers_base_scope` is `distinct.sorted`, so
  plucking two columns from it needs `reorder(nil)` first.
- **`.or` must come before `.distinct`, not after.** ActiveRecord refuses to
  combine relations that differ in `distinct`, so an OR chain has to be built
  first and made distinct at the end. `StatusListQuery` does exactly that.
- **MariaDB 10.11 rejects a table alias in a single-table `DELETE`.**
  PostgreSQL and MySQL 8.4 both accept it, so a statement can pass six of the
  nine cells and fail three. `DELETE FROM t alias WHERE …` has to be written
  without the alias.
- **`mariadb -e "…" | head` reports `head`'s exit status, not MariaDB's**, and
  MariaDB echoes a failing statement instead of an obvious error. A quick CLI
  probe through a pipe can say "it works" when it does not.
- **MariaDB *can* be installed in this container** — `apt-get install -y
  mariadb-server libmariadb-dev`, then `mariadbd --user=mysql
  --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock` in the background,
  a `redmine` user with `GRANT ALL`, and `dev/setup.sh <branch> mysql <ruby>`.
  Earlier sessions recorded that it could not be; that is no longer true, and it
  is worth the four minutes for anything touching SQL.
- **A unique index cannot enforce a key with a nullable column** on any of the
  three supported databases. This is why external F06 was answered with an
  idempotency test and a repair task rather than a constraint.
- **A cache built from the rules is not invalidated by the scope writer.**
  `Resolver.reset_cache!` clears both request caches, but it has to be *called*,
  and three of the write paths did not. If you add a cache, ask which table it
  actually depends on, not which table decides the answer.
- **InnoDB refuses to drop the last index with a foreign key's column
  leftmost** (MySQL error 1553). Migration 005 checks for its replacement first.
- **Rendering from a Redmine `before_action` answers before `require_admin`.**
  Core declares its own finders before the authorization callback, so anything
  a plugin renders from one of them is returned to whoever asked. Collect and
  let the action decide.
- **A migration's effect is invisible to the process that ran it.**
  `connection.table_exists?` still answered `true` after `drop_table` in the
  same `rails runner`, so a check written in one process proves nothing.
  `dev/check-backfill.sh` therefore runs each step as its own process.
- **PostgreSQL will not cast a text literal to a timestamp inside a `SELECT`
  list.** `INSERT ... SELECT 'value', '2026-...'` fails with a
  `DatatypeMismatch` where the same literal in a `VALUES` list is accepted. The
  backfill uses `CURRENT_TIMESTAMP`.
- **A spec that fails while creating a project poisons the database for later
  runs.** `projects_trackers` is not in any spec's fixture list, so rows for a
  project that was created and never destroyed survive; the `projects` sequence
  then hands the same id to the next run and `Project.create!` dies on
  `projects_trackers_unique`. To clear them: `DELETE FROM projects_trackers pt
  WHERE NOT EXISTS (SELECT 1 FROM projects p WHERE p.id = pt.project_id)`.
- **A new project already has `Setting.default_projects_modules` enabled.**
  Pushing another `EnabledModule.new(name: 'issue_tracking')` onto it makes the
  association invalid, and the error ("Enabled modules is invalid") does not say
  why. Guard with `module_enabled?`.
- **`Project#archive!` is private; `Project#archive` is not.** Use the latter,
  and assert its return value — it can refuse.
- **Redmine's I18n applies only the `one`/`other` plural forms to Polish.**
  `few:` and `many:` entries are silently ignored, so a Polish plural has to be
  phrased in a way that works for every count above one.
- **A YAML value containing `": "` needs quoting.** `ruby -ryaml -e
  'YAML.unsafe_load_file(ARGV[0])'` over `config/locales/*.yml` catches it.
- **The Bash tool's working directory persists between calls.** A `cd` into
  `.redmine/<version>` earlier in a session makes the next relative-path edit
  rewrite the *host's* file rather than the plugin's — or fail outright. Prefix
  edits with an explicit `cd /home/user/redmine_project_workflows &&`.
- **`dev/run.sh` always runs the whole spec directory.** Extra arguments are
  appended to `plugins/redmine_project_workflows/spec`, and a path argument has
  to be written relative to the *host* root, not the plugin root.
- **`Rails.application.config.to_prepare` in `init.rb` never runs.** Redmine
  loads `init.rb` from inside a `to_prepare` block, so the body of the file is
  the hook.
- **Never let `spec/spec_helper.rb` apply the patches itself.** The fallback
  that did was removed because it hid a change that left the plugin doing
  nothing in a real installation.
- **Redmine 7.0 has no `request_store`.** Use
  `RedmineProjectWorkflows::Current` for anything request-scoped, and reset it
  in specs — the Rails executor does not wrap an RSpec example, so
  `spec_helper` resets it before each one.
- **The plugin is copied into the Redmine host, not symlinked.** The specs
  resolve `config/environment` relative to their own real path; through a
  symlink that lands outside the host and every spec fails to load.
- **Run the migration checks before the suite.** Rails' `maintain_test_schema`
  reloads `db/schema.rb` when the suite starts and wipes the plugin's migration
  bookkeeping; after that `VERSION=0` silently does nothing and proves nothing.
  This applies to `dev/check-backfill.sh` too.
- **`render_404` does not abort the action.** It renders and returns `false`.
  In a `before_action` Rails halts the chain, so core gets away with it; inside
  an action it does not. See finding G01 for the other side of that coin: in a
  `before_action` it halts the chain *before* `require_admin`.
- **`User#roles_for_project` caches memberships on the object.** Re-fetch with
  `User.find(id)` after changing a member's roles.
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.** Without
  it the main config's `Exclude` lists replace `.rubocop_todo.yml`'s instead of
  adding to them, and 38 grandfathered offences come back.
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** The workflow
  controller, helper and all three views are byte-identical between 6.1 and
  7.0. What changed at 6.0 is that CSS icons became SVG sprites. Version
  differences belong in `RedmineProjectWorkflows::VersionHelper`.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`. Create the second project in the spec rather than
  reusing a fixture whose memberships you have not read.
- **`safe_attributes=` sets `project_id` before `tracker_id`**, on purpose and
  with a comment in core saying so. `Issue#tracker=` relies on it: the project
  has to be known before the tracker change can be resolved against it.
- **Rails casts oddly in `where(id:)`.** `Project.where(id: ['1e5'])` returns
  project 1. Every controller therefore checks the *shape* of an id
  (`/\A\d+\z/`) before querying, and compares the resolved ids back against the
  strings that were sent.
- **A workflow rule can make an issue invalid.** A generic `due_date required`
  rule makes `Issue.create!` fail in a spec that arranges the rule first.
  Create the issue first, or use `Issue.new`.

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
