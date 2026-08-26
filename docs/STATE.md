# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** none started. WP0..WP7 are specified in
  `docs/implementation-plan.md` and nothing has been built yet.
- **What exists:** the plugin as shipped in 0.0.3, plus a reproducible test
  harness, a characterization suite that pins the known defects, and — as of
  this session — the agent framework this file is part of.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. It overrides whatever name
  the environment gives a session. Two earlier commits sit on
  `claude/redmine-workflows-review-zpugog`, which `claude/dev` was branched
  from; that branch is history now, do not add to it.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open findings:** 16, across two files in `docs/review/findings/`. Every one
  is scheduled into a work package. Nothing is open that the plan does not
  cover.

## What the last sessions produced

**Verification.** An external review of commit `6c17b31` arrived in chat. It
had been written without the ability to run anything. Six Redmine hosts were
built — 5.1.13, 6.1 and 7.0.0, each against PostgreSQL 16 and MariaDB 10.11 —
and every claim was reproduced as a spec. Ten of its eleven findings stand,
three for a heavier or different reason than reported; one is a control rather
than a defect. Six further findings came out of the verification, mostly from
asking which of Redmine's own queries read the `workflows` table without
knowing that projects exist.

The most consequential correction: the external review says an *empty* project
override cannot be expressed. True, and the same mechanism means a *partial*
one cannot either — one project rule removes every generic transition for that
tracker and role. The administration UI masks this, which is why it survived
production use: selecting a project with no rules shows an empty matrix, so an
administrator fills in the whole set and gets a full override that works
correctly.

**Test harness.** `dev/setup.sh` builds a Redmine host for a given branch and
database; `dev/run.sh` syncs the working tree into it and runs the suite. CI
was replaced by a nine-cell matrix on push and pull request; the two previous
workflows had never run automatically.

**This session.** The agent framework, adapted from `redmine_ai_triage`:
`CLAUDE.md` with nine plugin-specific invariants, `docs/design.md`,
`docs/adr/ADR-001-scope-model.md`, `docs/implementation-plan.md`,
`docs/DECISIONS.md`, `docs/TASK-PROMPT.md`, the review loop in `docs/review/`
with both existing reviews seeded as findings files, RuboCop, and three CI
gates that were missing.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1 + PostgreSQL 16 | 82 examples, 0 failures |
| Plugin suite, 5.1 + MariaDB 10.11 | 82 examples, 0 failures |
| Plugin suite, 6.1 + PostgreSQL 16 | 82 examples, 0 failures |
| Plugin suite, 6.1 + MariaDB 10.11 | 82 examples, 0 failures |
| Plugin suite, 7.0 + PostgreSQL 16 | 82 examples, 0 failures |
| Plugin suite, 7.0 + MariaDB 10.11 | 82 examples, 0 failures |
| RuboCop | 40 files, no offences (181 grandfathered in `.rubocop_todo.yml`) |
| `zeitwerk:check` on 7.0 | "All is good!" |
| Five Deface overrides on 7.0.0 / Rails 8.1 | all five reach the rendered page |

## Exact next step

Start **WP0** from `docs/implementation-plan.md`. Six repairs, none of which
touch the data model and none of which have to be redone later. The first one
(the SVG sprite in the project selector) is the only defect that makes the
plugin actively worse on a supported version, so start there.

For each: invert or rewrite the matching example in `spec/characterization/`
and move it into the normal spec directories. WP0 is finished when its six
findings are `fixed` in the findings files and the suite is green on at least
5.1 and 7.0.

## Known traps

- **The plugin is copied into the Redmine host, not symlinked.** The specs
  resolve `config/environment` relative to their own real path; through a
  symlink that lands outside the host and every spec fails to load with
  `cannot load such file -- /home/config/environment`. `dev/sync.sh` copies.
- **Run the migration reversibility check before the suite.** Rails'
  `maintain_test_schema` reloads `db/schema.rb` when the suite starts and wipes
  the plugin's migration bookkeeping; after that `VERSION=0` silently does
  nothing and proves nothing.
- **`render_404` does not abort the action.** It renders and returns `false`.
  Every call needs `return if performed?` after it, or the next render raises
  `DoubleRenderError` and the user gets a 500 with a 404 page half sent.
- **`User#roles_for_project` caches memberships on the object.** A spec that
  changes a member's roles and then reuses the same `User` instance measures
  the old roles. Re-fetch with `User.find(id)`. One verification run reported a
  bug that was only this.
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.** Without
  it the main config's `Exclude` lists replace `.rubocop_todo.yml`'s instead of
  adding to them, and 38 grandfathered offences come back.
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** The workflow
  controller, helper and all three views are byte-identical between 6.1 and
  7.0. What changed at 6.0 is that CSS icons became SVG sprites.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`, so an issue there yields no workflow roles and an
  empty status list that looks like a plugin bug. Create the second project in
  the spec rather than reusing a fixture whose memberships you have not read.

## Development environment (rebuild from scratch in a fresh session)

```bash
# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (repeat per version/database)
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/run.sh .redmine/5.1-stable-postgresql

# lint
BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant.

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```
