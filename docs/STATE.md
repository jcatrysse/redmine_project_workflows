# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 and WP1 are **done**. WP2 is next and has not been
  started. WP0..WP7 are specified in `docs/implementation-plan.md`.
- **What exists:** the plugin as shipped in 0.0.3, the WP0 repairs, and — as of
  this session — the scope model. `project_workflow_scopes` exists, is
  backfilled, and is the only thing that decides whether a project runs its own
  workflow. The central defect is fixed: a project that inherits and a project
  with a deliberately empty workflow are now different rows, not the same
  absence of rows.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/docs-review-giaqq0`, which the environment had prescribed; nothing was
  committed there.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** none.
- **Open findings:** 8 of 16. WP1 closed external F01 (an empty project override
  cannot be represented — the finding the whole scope model exists for) and
  external F07 (the hot-path override check is system-wide and badly indexed).
  External F06's scope-table half is done; its `workflows` half stays in WP2.
  External F04's `Resolution:` pointed at WP1 and now points at WP2, where the
  plan and the characterization file always put it.
- **`spec/characterization/`:** one file, four examples, all in
  `known_issues_spec.rb`. They belong to WP2 (`Tracker#issue_status_ids`,
  `Project#rolled_up_statuses`, the used-statuses filter) and WP3 (the summary
  page count). The plan is finished when the directory is empty.

## What this session produced

**The scope table.** `project_workflow_scopes` holds one row per (project,
tracker, role, rule type). Its presence is the decision to run an own workflow;
its absence is inheritance. Existing installations are backfilled — every
(project, tracker, role) that had rules gets a scope of the matching type — so
behaviour after the migration is the behaviour before it.

**The resolver decides on scopes.** `Resolver`, `TransitionQuery`,
`PermissionQuery` and `StatusListQuery` now ask the scope table, never "do any
rows exist". The lookup is cached per request in
`RedmineProjectWorkflows::Current`, keyed by (project, tracker, rule type), so
an issue list of one tracker in one project costs one query rather than one per
issue.

**The three actions of INV-3**, in `ScopeWriter` and reachable from the two
admin matrices through a panel above the grid: give the project its own workflow
(a copy of the generic one, or empty), empty the matrix (the scope stays), and
return to inheritance (scope and rules both go). The panel names the state in
words — *Own workflow*, *Own empty workflow*, *Inherits the generic workflow* —
and renders nothing at all when only the generic workflow is selected, so an
administrator who does not use the plugin sees core's screens unchanged.

**Two things came out differently from what the plan assumed.**

1. **The fallback to core had to go entirely, not be narrowed.** The plan said
   `override_active?` would become a lookup on the current project. Doing only
   that would have sent every *inheriting* project through core's own query —
   which carries no `project_id` predicate and would therefore have handed it
   the rules of every other project. The old system-wide check was the only
   thing hiding that. `Issue#new_statuses_allowed_to` and
   `#workflow_rule_by_attribute` are now always answered by the plugin; both
   core bodies are byte-identical across 5.1, 6.1 and 7.0, so reproducing them
   is safe, and `override_active?` is gone from both query services.
2. **The unique index on the scope table shipped here, not in WP2.** It is part
   of the table `design.md` specifies and the backfill has to produce unique
   rows anyway. WP2's remaining index work is the one on `workflows` itself.

**One gap WP1 would otherwise have opened.** Once rules alone stop meaning
"this project overrides", the copy screen's `duplicate` action writes rows that
the resolver ignores. It now records a scope for what it copied — and only where
the target actually has rules, because an empty *transitions* scope would stop
every issue in that project from changing status. WP2 still owns the
role/tracker copy path (`WorkflowRule.copy`).

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 178 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 178 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 178 examples, 0 failures |
| CI, all nine cells + RuboCop | green on `5fcf02d` (run 9) and on `899dc8a` (run 10) |
| RuboCop | 54 files, no offences |
| `zeitwerk:check` | "All is good!" on 5.1, 6.1 and 7.0 |
| Migration reversibility up → 0 → up | clean on 5.1, 6.1 and 7.0, run before the suite |
| Backfill (`dev/check-backfill.sh`) | passes on 5.1, 6.1 and 7.0, run before the suite |
| New specs against the old decision rule | 8 fail — see below |
| Locale keys resolve, `en` and `nl` checked by hand | verified with `I18n.t` on a booted host, including the counted forms |

**The failing-on-old-code check was made precise.** Reverting the whole of
`lib/` produced noise (missing methods). Instead only the pre-ADR-001 *decision
rule* was put back — `overridden_role_ids_for` asking `model.where(project_id:,
tracker_id:, role_id:)` and `StatusListQuery` doing the same — leaving the rest
of WP1 in place. Eight examples fail, and they are exactly the ones that state
the three-state model: the two "ignores a project row when the project has no
scope", the two "allows nothing for a scope without rules", "keeps the generic
workflow when a project rule exists without a scope", "allows no transition at
all when the scope is left without rules", "tells an empty own workflow apart
from inheritance", and the resolver cache invalidation.

MySQL and MariaDB could not be run locally: no server for either is available in
this container and the packages could not be installed. CI covered those six
cells twice: run 9 on `5fcf02d`, which carries the whole of WP1, and run 10 on
the branch head. Both are green on all nine cells plus RuboCop, and both ran the
new backfill gate. Nothing is left unverified.

**Two claims in this session's history had to be corrected, both caught by
checking rather than assuming.** A commit message asserted that three new
examples fail on the previous commit; running it showed all three pass, because
two of the behaviours had already shipped with the WP1 commit and the third had
no test pinning it at all. The commit was amended: a helper example was added
that does fail on the old code (178 examples, 1 failure when the one file is
reverted), and the message now says which behaviours are new and which are
merely newly covered. Verify the "fails on the old code" claim by running it,
every time.

## Exact next step

Start **WP2** from `docs/implementation-plan.md`, and finish
`spec/characterization/` while doing it. In order:

1. `Project#rolled_up_statuses` loses the role filter and computes effective
   statuses per project across the tree, then unions (external F08). This
   inverts the `known_issues_spec.rb` example about member-less projects.
2. The two `Issue` call sites that consult `Tracker#issue_status_ids` become
   project-aware; the tracker method itself stays a global union (claude F02 —
   read its `Resolution:` for why the obvious fix is wrong). Inverts the
   `issue_status_ids` example.
3. `WorkflowRule.copy` carries project rules **and their scopes**, so copying a
   role or tracker produces a working copy (claude F03). The copy *screen* was
   already handled in WP1; this is the role/tracker duplication path in core.
4. The used-statuses filter in `WorkflowsController#find_statuses` — still row
   based, still the last matrix query that ignores scopes. Inverts the
   "used statuses filter" example.
5. Index and idempotency work on `workflows` itself (external F06). The scope
   table's unique index is already in place.
6. Walk the remaining core queries against `workflows` (default data loader,
   status deletion) and record the outcome in `design.md`.

## Known traps

Everything below cost time at least once. The first five are new this session.

- **A migration's effect is invisible to the process that ran it.**
  `connection.table_exists?` still answered `true` after `drop_table` in the
  same `rails runner`, so a check written in one process proved nothing.
  `dev/check-backfill.sh` therefore runs each step — migrate, seed, migrate
  down, migrate up, assert — as its own process.
- **PostgreSQL will not cast a text literal to a timestamp inside a `SELECT`
  list.** `INSERT ... SELECT 'value', '2026-...'` fails with a
  `DatatypeMismatch` where the same literal in a `VALUES` list is accepted. The
  backfill uses `CURRENT_TIMESTAMP`, which every supported adapter spells the
  same way and which Rails has already put in UTC.
- **A spec that fails while creating a project poisons the database for later
  runs.** `projects_trackers` is not in any spec's fixture list, so rows for a
  project that was created and never destroyed survive; the `projects` sequence
  then hands the same id to the next run and `Project.create!` dies on
  `projects_trackers_unique`. If specs start failing that way, delete the
  orphans: `DELETE FROM projects_trackers pt WHERE NOT EXISTS (SELECT 1 FROM
  projects p WHERE p.id = pt.project_id)`.
- **Redmine's I18n applies only the `one`/`other` plural forms to Polish.**
  `few:` and `many:` entries are silently ignored, so a Polish plural has to be
  phrased in a way that works for every count above one; `pl.yml` puts the
  number after the noun for exactly that reason.
- **A YAML value containing `": "` needs quoting.** The Polish rewrite above
  broke the file until the two affected lines were quoted. `ruby -ryaml -e
  'YAML.unsafe_load_file(ARGV[0])'` over `config/locales/*.yml` catches it.
- **The Bash tool's working directory persists between calls.** A `cd` into
  `.redmine/<version>` earlier in a session makes the next `python3` edit rewrite
  the *host's* file rather than the plugin's. Prefix edits with an explicit
  `cd /home/user/redmine_project_workflows &&`, or check `git status` afterwards.
- **`dev/run.sh` always runs the whole spec directory.** Extra arguments are
  appended to `plugins/redmine_project_workflows/spec`, and a path argument has
  to be written relative to the *host* root
  (`plugins/redmine_project_workflows/spec/...`), not the plugin root.
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
  `dev/sync.sh` copies.
- **Run the migration checks before the suite.** Rails' `maintain_test_schema`
  reloads `db/schema.rb` when the suite starts and wipes the plugin's migration
  bookkeeping; after that `VERSION=0` silently does nothing and proves nothing.
  This applies to `dev/check-backfill.sh` too.
- **`render_404` does not abort the action.** It renders and returns `false`.
  In a `before_action` Rails halts the chain, so core gets away with it; inside
  an action it does not, and the next render raises `DoubleRenderError`.
- **`User#roles_for_project` caches memberships on the object.** A spec that
  changes a member's roles and then reuses the same `User` instance measures
  the old roles. Re-fetch with `User.find(id)`.
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.** Without
  it the main config's `Exclude` lists replace `.rubocop_todo.yml`'s instead of
  adding to them, and 38 grandfathered offences come back.
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** The workflow
  controller, helper and all three views are byte-identical between 6.1 and
  7.0. What changed at 6.0 is that CSS icons became SVG sprites. Version
  differences belong in `RedmineProjectWorkflows::VersionHelper` and nowhere
  else.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`, so an issue there yields no workflow roles and an
  empty status list that looks like a plugin bug. Create the second project in
  the spec rather than reusing a fixture whose memberships you have not read.
- **Rails casts oddly in `where(id:)`.** `Project.where(id: ['1e5'])` returns
  project 1, and `'01'` resolves to project 1 too. Every controller therefore
  checks the *shape* of an id (`/\A\d+\z/`) before querying, and compares the
  resolved ids back against the strings that were sent.
- **A workflow rule can make an issue invalid.** A generic `due_date required`
  rule makes `Issue.create!` fail in a spec that arranges the rule before
  creating the issue. Create the issue first, or use `Issue.new`.

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

# the two migration gates, BEFORE the suite
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
