# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 is **done**. WP1 is next and has not been started.
  WP0..WP7 are specified in `docs/implementation-plan.md`.
- **What exists:** the plugin as shipped in 0.0.3, a reproducible multi-version
  test harness, the agent framework, and — as of this session — the six WP0
  repairs. The data model is still unchanged: `workflows.project_id` and
  nothing else. The scope table does not exist yet, so the central defect
  (a project that inherits cannot be told apart from one with a deliberately
  empty workflow) is still there. That is WP1.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/docs-review-7d85xt`, which the environment had prescribed; nothing was
  committed there. All work is on `claude/dev`.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open findings:** 10 of 16. Six were closed in WP0 (claude F04, F05;
  external F02, F03, F05, F09). Every remaining one is scheduled into a work
  package.
- **`spec/characterization/`:** four examples left, down from nine. They belong
  to WP2 (`Tracker#issue_status_ids`, `Project#rolled_up_statuses`, the used
  statuses filter) and WP3 (the summary page count). The plan is finished when
  the directory is empty.

## What this session produced

Six repairs, and two corrections to what the plan asked for.

**The repairs.** The project selector renders the SVG sprite core has expected
since 6.0, so the workflow page's JavaScript no longer aborts on 6.x and 7.0.
`duplicate` decides on the plugin's parameters rather than on a resolved
project list, so "copy to the generic workflow only" stops falling through to
core and ignoring the chosen source project. `load_project_options` renders
nothing and reports what it rejected, so an invalid project id is a translated
validation error or a clean 404 instead of a `DoubleRenderError`. Both writers
whitelist rule names, cell values, field names and status ids against
server-built lists, which restores validations core had and the plugin's
routing had removed from the generic write path as well. `Thread.current` is
gone. Patches are applied where a reload actually reaches them.

**The two corrections**, both found by reading the host source and then booting
it, and both recorded in the findings files and in `docs/DECISIONS.md`:

1. **`config.to_prepare` is a silent no-op in a Redmine plugin's `init.rb`.**
   `Rails::Application::Configuration#to_prepare` only appends to
   `config.to_prepare_blocks`, and the `:add_to_prepare_blocks` initializer has
   already consumed that array by the time Redmine's `PluginLoader` loads any
   `init.rb` — which it does from inside a `to_prepare` block of its own. The
   change was written as the plan asked, and a freshly booted 7.0 then reported
   every patch missing while the suite stayed green, because `spec_helper.rb`
   re-applied them itself. `apply_patches` is now called in the body of
   `init.rb`, which *is* the reload window. `CLAUDE.md`'s forbidden-constructs
   table prescribed the broken form and has been corrected.
2. **Redmine 7.0 no longer bundles `request_store`.** The review called the
   `Thread.current` branch dead code on that premise; on 7.0 it was the only
   path the cache ever took. The cache is now
   `RedmineProjectWorkflows::Current`, an `ActiveSupport::CurrentAttributes`
   subclass, which Rails resets around every request on all three versions.

**One defect nobody had found.** Dropping rejected entries before the delete
rather than only before the insert also fixed this: a transitions cell whose
three rules were all left at "no change" arrived at the writer as an empty rule
hash, which still contributed to the delete predicate and then inserted
nothing. "Leave this as it is" removed the transition. There is a regression
test.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 103 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 103 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 103 examples, 0 failures |
| RuboCop | 43 files, no offences |
| `zeitwerk:check` | "All is good!" on 5.1, 6.1 and 7.0 |
| Migration reversibility up → 0 → up | clean on 5.1, 6.1 and 7.0, run before the suite |
| New specs against the old code (`HEAD~1`) | 21 fail, including every inverted characterization example |
| Patches installed by the host boot | verified with `rails runner` on 5.1 and 7.0, with `spec_helper`'s fallback removed |

**Not run this session:** MySQL and MariaDB. No server for either is available
in this container and the packages could not be installed. CI runs all nine
cells on push, so the first thing to check next session is that the WP0 push
went green there.

## Exact next step

Start **WP1** from `docs/implementation-plan.md`: the `project_workflow_scopes`
table, the model, the resolver rewrite and the backfill. This is the package
everything after it depends on, and it is the one that fixes the defect the
whole scope model exists for.

Order within it: migration and backfill first (reversible, tested up → down →
up **before** the suite runs), then `ProjectWorkflowScope`, then teach
`Resolver`, `TransitionQuery`, `PermissionQuery` and `StatusListQuery` to decide
on scopes instead of on row existence, then the writers, then the three actions
in the admin screens. Finish by inverting the override-semantics examples in
`spec/characterization/override_semantics_spec.rb`.

## Known traps

- **`Rails.application.config.to_prepare` in `init.rb` never runs.** See above.
  Redmine loads `init.rb` from inside a `to_prepare` block, so the body of the
  file is the hook. This one cost a whole review cycle to catch, because the
  suite stayed green.
- **Never let `spec/spec_helper.rb` apply the patches itself.** The fallback
  that did was removed for exactly that reason: it hid a change that left the
  plugin doing nothing in a real installation.
- **Redmine 7.0 has no `request_store`.** Use
  `RedmineProjectWorkflows::Current` for anything request-scoped, and reset it
  in specs — the Rails executor does not wrap an RSpec example, so
  `spec_helper` resets it before each one.
- **The plugin is copied into the Redmine host, not symlinked.** The specs
  resolve `config/environment` relative to their own real path; through a
  symlink that lands outside the host and every spec fails to load with
  `cannot load such file -- /home/config/environment`. `dev/sync.sh` copies.
- **Run the migration reversibility check before the suite.** Rails'
  `maintain_test_schema` reloads `db/schema.rb` when the suite starts and wipes
  the plugin's migration bookkeeping; after that `VERSION=0` silently does
  nothing and proves nothing.
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
  project 1, and `'01'` resolves to project 1 too. Both controllers therefore
  check the *shape* of a project id (`/\A\d+\z/`) before querying, and compare
  the resolved ids back against the strings that were sent.

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

# sync the working tree and run the suite
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-postgresql

# lint (rubocop's binaries are not on PATH by default in this container)
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant. `dev/setup.sh` and `dev/run.sh` now put
rbenv's *shims* on `PATH` rather than assuming that finding `rbenv` is enough.

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```
