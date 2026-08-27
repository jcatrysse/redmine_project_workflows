# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP8** are done and have been for four
  sessions. `docs/implementation-plan.md` runs WP0..WP8 and every row reads
  *done*. There is no WP9. What happens now is the **review loop** in
  `docs/review/`.
- **This session was the fixer**, on a review somebody else ran. An independent
  Claude session reviewed `ed4073d`, found nine things, and pushed
  `docs/review/findings/2026-08-27-claude.md` to `main`. All nine are answered:
  **eight `fixed`** and one **`adjusted`** (F04 — the defect is real and the
  reviewer's reasoning about it was not; the `Resolution:` line says how).
  Nothing is left at `open` or `question`. F09 was filed as a `question` because
  it was not a fixer's to settle, and **Jan answered it the same day** — see
  "Open choices" below.
- **Where the answered findings file is:** on `claude/dev`, which is what
  `docs/review/README.md` prescribes — a fixer pushes to `claude/dev`, a reviewer
  pushes a findings file to `main`. So the copy on **`main` still reads nine
  `open` findings** and will until Jan merges. That trap is no longer implicit:
  `docs/review/README.md` now says out loud that a fixer answers the file on
  `claude/dev` and that `main`'s copy therefore keeps the original statuses, and
  tells the reader to take a findings file from `claude/dev` before believing its
  `Status:` lines. It was the shape of the mistake `G03` made, and it was half of
  what F09 was about.
- **What exists:** the plugin at **0.1.3**. 0.1.0 is the scope model and the
  eight work packages; 0.1.1 is the two matrix-save repairs; 0.1.2 is the two
  concurrency repairs; 0.1.3 is this session — one operability defect that bites
  on a large installation, and seven edges, three of which are the same shape: a
  screen reporting success for something it did not do.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/review-findings-f01-f08-o8vmkn`, which the environment minted.
  **Read this before running the branch commands:** the local `claude/dev` in
  this fresh container had a history *unrelated* to `origin/claude/dev` — no
  merge base at all, `git rev-list --left-right --count` said 5 and 50, and
  `git pull --ff-only` aborted with "Not possible to fast-forward". The remote
  is the real branch. `git checkout -B claude/dev origin/claude/dev`, or
  `git reset --hard origin/claude/dev` once checked out, is the form that works;
  `git pull --ff-only` is not. Check with
  `git merge-base --is-ancestor claude/dev origin/claude/dev` before trusting a
  local `claude/dev` at all.
- **`main`:** unchanged apart from the two commits the reviewer pushed (the
  findings file and its addendum). Jan asks for the merge himself. Two things
  worth knowing before he does. First, `main` still carries the *old* two-cell
  CI (`rspec-51.yml`, `rspec-60.yml`) while the nine-cell `specs.yml` exists
  only on `claude/dev`; the merge replaces them and the two old names linger in
  GitHub's workflow list with no file behind them, which is cosmetic. Second,
  `origin/main`'s history is **unrelated** to `origin/claude/dev`'s — they share
  no merge base — so the merge needs `--allow-unrelated-histories` or a
  deliberate replacement of `main`'s tree. That is half of finding F09.
- **Open findings:** **one** — `G02`, the batching pass for a cross-project bulk
  tracker change, deferred with the reasoning recorded, in
  `docs/review/findings/2026-08-26-wp2-observations.md`. To check:
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` — one hit plus a
  line in `TEMPLATE.md`, which is not a finding.
- **`spec/characterization/`:** still **gone**, since WP3.
- **Open choices:** **none.** The two this session filed, Jan answered the same
  day: **A and A** — the review loop names `claude/dev` rather than `main`
  (F09), and the deleted `.codex/` scripts stay deleted (F08). Both are in
  `docs/DECISIONS.md` under "Decided (Jan) — 2026-08-27", and the "Open — for
  Jan" section is empty. That matters for a reason this repository has already
  been bitten by: `G03` spent a session marked *open* in its findings file after
  Jan had answered it, because only the ledger was updated. Here the findings
  file, the ledger and this file were all changed together.

## What this session produced

Nine findings, read in the order the fixing prompt set: F01 first, then F03 and
F06 together because they are one theme, then F02, F05 and the nits.

### F01 — the Save form turned "All projects" into a list of every project id

The project selector and the matrix are two separate forms in Redmine's own
`workflows/edit` — byte-identically on 5.1, 6.1 and 7.0 — so two hidden fields
are the only thing that carries the selection from the selector into the save.
They expanded the `all` keyword into every project id plus `global`. After that
the selection was no longer `all` for the rest of the session: the redirect after
Save named 500 projects on an installation with 500 of them, which is roughly
11 KB of query string in a `Location` header, and nginx's default
`large_client_header_buffers` is 8 KB — so the save succeeded and the
administrator got a 414. Under that threshold the failure was quieter, with all
four scope-action links on the page carrying the same list.

The repository already held the rule, in one of two places: the scope panel four
files away keeps the keyword verbatim, says in a comment why, and has a spec
asserting it. The two overrides now do the same, and `load_project_options`
expands `all` server-side as it always did.

### F03 and F06 — a screen reporting success for something it did not do

Three instances, one shape.

**A save whose payload the whitelist emptied.** The writers returned only what
they had *refused*, and the controller worked out what had been written by
subtracting that from the size of the selection. That is right only while "not
refused" means "written". A request whose every value fails the whitelist is
dropped before the delete — deliberately, so an unacceptable value leaves the
rule it names alone rather than clearing it, which the README promises — and it
never reaches the scope rows, so it refuses nothing. It arrived at the flash as
a successful save of the whole selection.

The writers now return a `MatrixSaveResult` with both counts, and the duplicated
arithmetic is gone from the controller. A save that wrote nothing and refused
nothing gets a message of its own.

**The same thing on a project's own workflow screen**, which set the notice
whenever the request carried a matrix at all — including for a save that lost
the race against a concurrent *return to the generic workflow*, which 0.1.2
taught the writer to refuse and which was still reported as a success.

**A copy that empties a workflow.** Copying into a project deletes the target
pair's rows across *both* rule types and then inserts whatever the source has, so
a source with no rules of one kind leaves the target's scope of that kind
standing and empty. That is an own **empty** workflow, in which nothing is
permitted and, for transitions, no issue in the project can change status —
exactly the state ADR-001 wants unreachable by accident. Refusing was the wrong
fix, because the copy is also the way somebody deliberately empties a project.
So the copy counts the combinations it left that way and names them.

### F04 — the audit stamp, and a finding that was right for the wrong reason

Worth reading carefully, because the difference decided the shape of the fix.
The finding says a copy that moves only transitions still stamps the target's
field-permission scopes as edited. It does — and that stamp is **correct**:
`copy_for_project` deletes the target pair's rows of both rule types before
inserting anything, so such a copy has just deleted every field permission the
target had. "Updated by Jan, 2 minutes ago" is true.

What is genuinely wrong is narrower and was reachable. The stamp covered the
cross product of the target trackers and roles, and `copy_for_project` **skips**
a pair whose source resolves to the target itself. *Source: any project, any
role, this tracker* into that same tracker and role copies nothing at all, and
every combination it named was stamped anyway.

`copy_for_project` now returns the pairs it copied; the controller turns those
into (project, tracker, role) triples; `ScopeWriter.touch_combinations` stamps
exactly those. `touch_scopes`, which stamps a cross product, stays for the matrix
save — there the cross product genuinely is what was rewritten.

That distinction also produced a new service. `ScopeCombinations` holds the
questions a *set of exact triples* can be asked, as opposed to three id lists
whose cross product is the selection. Reading the cross product and using the
answer whole is what F04 was, so the two shapes now have two names.

### F05 — a workflow in force with no line on the screen meant to explain it

The project's Workflow tab lists the roles that have members in the project.
Jan decided on 2026-08-26 that it should offer only those, and that decision
stands. What did not hold was one sentence of its stated premise: that the other
roles "go on following the generic workflow". They do not have to. A system
administrator can give a project its own workflow for *Non member* or
*Anonymous* from Administration → Workflow, and the last member holding an
ordinary role can leave. Either way the project ran its own workflow for a role
its own tab neither showed nor could undo — and a project manager asking "why
can anonymous visitors not move issues here" had no path from the screen that
answers that question to the state that causes it.

The tab now lists such a row, and it can be opened, emptied and returned to the
generic workflow. The one thing it is not offered is a *new* workflow of its own,
which is the decision, enforced by a 403 on `#enable` alone. The comment in
`ProjectOptions.roles`, the README paragraph and the table in `docs/design.md`
have stopped saying the thing that was not true.

### F02, F07, F08 — the build, a comment and a deletion

`.rubocop.yml` declared `TargetRailsVersion: 8.1`, the Rails of the *newest*
supported host. That configures the lint gate to push code towards APIs the
oldest host does not have: a contributor writes `params.expect`, the cop that
demanded it is satisfied, the lint job is green, and the plugin raises
`NoMethodError` on Redmine 5.1. A gate that approves what the plugin cannot run
is worse than no gate. It is `6.1` now, and a spec inside the suite asserts the
property from every host, so the 5.1 cell fails if it drifts upwards again.

`duplicate` never runs the project-selection check that `copy` runs, which reads
like an omission and is not: the action does not read `params[:project_id]` at
all, so a value there names nothing and can widen nothing. It says so now, and a
characterising example pins the choice.

The three `.codex/` scripts are gone. Nothing referred to them; they named
Redmine 6.0 as supported and 7.0 not at all; and their `rsync` would have copied
every built host in `.redmine/` into the plugin directory. `dev/README.md` says
`dev/` is the only supported path and names the directory that used to exist, so
the next session recognises a stale copy rather than building from it.

### The tests

**Forty-two new examples.** They fall into three groups, and the difference
matters, because "I added tests" and "I proved the defect" are not the same
claim:

- **Fifteen were run red against `c3047cf` and then made green.** These are the
  proof. Two deface examples for F01, one for F02, two for F03/F04, six for F06
  across the two controllers, and four for F05.
- **Eight pass on the old code, and are said so here and in the findings file.**
  The two F01 controller examples (`update` / `update_permissions` with
  `project_id: ['all']`) are the coverage gap the finding named rather than the
  proof of the defect — the expansion happened in the *form*, so a controller
  driven with `['all']` directly always behaved correctly. The rest are
  companions asserting the other half of a case (a copy that emptied nothing says
  nothing; a rejected value leaves its rule alone; a combination the copy *did*
  write is still stamped) and the F07 example, which characterises a deliberate
  asymmetry.
- **Nineteen exercise code that did not exist**, so a run against the old tree
  is a `NoMethodError` and proves nothing: the sixteen in
  `spec/services/scope_combinations_spec.rb`, the two for
  `ScopeWriter.touch_combinations`, and the settings tab's query-count example.
  They are edge and failure cover for the new code — nil and empty input, a
  malformed triple, a repeated one, and the cross-product trap from both ends —
  not evidence about the old behaviour.

Five existing examples were rewritten, none weakened: they asserted the writers'
old integer return (`expect(skipped).to eq(1)`) and now assert the two counts
(`expect(result).to have_attributes(written: 0, skipped: 1)`), which says
strictly more. Six `ensure_scopes_for_copy` call sites in
`spec/services/scope_writer_spec.rb` moved from three id lists to a list of
triples, for the same reason F04 did.

Method, because the previous two sessions were each fooled once by the wrong one.
Each red example was written and run **before** its fix, against the tree as it
then stood. The set was then re-confirmed against a pristine `c3047cf`, with the
fixes **committed first** — which is what makes the restore safe — by
`git checkout c3047cf -- app lib config`, leaving `spec/` and the docs at HEAD,
running the suite, and restoring with `git checkout HEAD -- app lib config`.
Never `git stash`: it exits 0 and says "No local changes to save" once the change
is committed, and turns the "old code" run into the new code passing itself.

That run gave **670 examples, 27 failures**, and every one of the 27 is
accounted for, which is the point of quoting the number:

- **14** are the red examples above — F01 (2), F03 (1), F04 (1), F05 (4) and
  F06 (6). The fifteenth is F02's, and this run could not show it: the value it
  asserts lives in `.rubocop.yml`, which is not under `app`, `lib` or `config`,
  so the run saw the corrected `6.1`. It was proved red on its own, by setting
  the value back to `8.1` and running the example, and green again on restoring
  `6.1`.
- **11** are the existing examples this session rewrote for the writers' new
  return type (5) and for `ensure_scopes_for_copy`'s new keyword (6). They fail
  against the old code by construction — that is what "rewritten" means — and
  neither rewrite weakened an assertion.
- **2** are the new `ScopeWriter.touch_combinations` examples, failing with
  `NoMethodError` because the method did not exist. Counted in the eighteen
  above, not in the fifteen: a missing method is not evidence about behaviour.

### What the review role caught in this session's own diff

Worth recording, because all three were the kind of thing that passes a green
suite:

- **`ProjectOptions.roles` ran twice per render**, once inside `visible_roles`
  and once to answer "is this role offered?" — in the settings tab *and* again in
  `ProjectWorkflowsController#find_tracker_and_role`. Two constant queries in
  each, not an N+1, but the fix is one optional argument and a memo the tab
  seeds, so there is no reason to carry it. Both are gone.
- **`docs/design.md`'s query count for the settings tab was wrong again**, which
  is the third time (it read "four" until WP6 and "six or seven" until now). This
  session measured it — 7, 8 or 9 depending on whether a role with no member has
  a scope and whether the audit line names anybody — and added an example that
  asserts the *property* with a bound, so the next change to the number cannot
  pass unnoticed.
- **`_scope_actions` treated a `nil` `offered` local as "not offered"**, which
  would silently remove a button. Every caller passes it, but silently removing a
  control is precisely the failure mode an unmatched Deface anchor already taught
  this plugin about, so `nil` now counts as offered.

### One thing noticed and deliberately not fixed

The **tracker** analogue of F05. `ProjectOptions.trackers` is the project's
enabled trackers, so a scope for a tracker that has since been taken off the
project has no row on the tab either — the same hole F05 named for roles. It is
*not* the same defect: a tracker that is not enabled has no issues in the
project, so its workflow is inert, where a role like *Anonymous* applies whether
anybody holds it or not. What is real, and small, is that re-enabling the tracker
brings the old scope silently back into force. Reported here rather than fixed,
per `CLAUDE.md`: it is outside the eight findings this session was given.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | **671 examples, 0 failures** (was 629; 42 added) |
| Plugin suite, 7.0-stable + PostgreSQL 16 | **671 examples, 0 failures** |
| Migration up → 0 → up | **clean on 7.0-stable + PostgreSQL**, run on a database rebuilt from *core* migrations only and **before** the suite touched that host. Leftovers after `VERSION=0`: `project_workflow_scopes` gone, `workflows.project_id` gone, plugin bookkeeping in `schema_migrations` empty. This session changes no migration — `git status -- db/` is empty — so it is a re-check rather than a new claim |
| Fails on the old code | **15 of the 42 new examples**, run rather than assumed, and re-confirmed against a pristine `c3047cf`. Of the other 27, eight pass on the old code and are named as such; nineteen exercise code that did not exist. See "The tests" above |
| RuboCop | **96 files, no offences**, through `.github/lint/Gemfile`, and **no new `.rubocop_todo.yml` entry**. Three `Metrics` limits were crossed on the way — `ClassLength` on `ScopeWriter`, `ModuleLength` on `WorkflowsControllerPatch`, `AbcSize` on `find_tracker_and_role` — and all three were fixed by extracting rather than by relaxing the cop; see the traps |
| Locale parity | **8 files × 96 keys**, no difference. Two keys added, translated by hand in all eight |
| JavaScript gate | not re-run: nothing in `_bulk_script.html.erb` changed |
| MySQL, MariaDB, and 6.1 | **not run locally** — two of the nine cells ran here; CI covers the other seven |
| CI | **run 88 green — all ten jobs**, on `d02333a`: nine cells (5.1 / 6.1 / 7.0 × PostgreSQL / MySQL / MariaDB) plus RuboCop, and within every one of the nine the *Plugin migrations are reversible (up → 0 → up)* step, the backfill check and the Zeitwerk check as well. That is the whole of this session's code on every supported combination, so MySQL 8.4 and the two MariaDB cells — the four this container did not run — have seen it. Runs 85 and 87 were *cancelled* by the concurrency group when the next commit was pushed, which is what a cancelled run here almost always means (see the traps) and not a failure; run 84 was the earlier green one, on the tree carrying every F01–F08 change. Name the run number rather than saying "green": every correction to this row is itself a commit and a new run, and the run for the commit that wrote *this* row is therefore one nobody has read |

## Exact next step

1. **Nothing to check first.** Run 88 was green on all ten jobs for `d02333a` —
   nine cells plus RuboCop, with the migration-reversibility, backfill and
   Zeitwerk steps green inside each cell. The only commit after it changes this
   file and nothing else, so its own run is the one thing nobody has looked at,
   and there is no code in it to fail.
2. **Then it is Jan's turn.** `docs/review/findings/2026-08-27-claude.md` is the
   readable account of all nine findings with a `Resolution:` line on each; the
   CHANGELOG's 0.1.3 entry is the same thing for a user.
3. **No choices are waiting.** Both were answered on the day they were filed.
4. If he wants more code, the candidates already written down are unchanged: the
   layered SVG diagram, the issue show page, row and column actions on the
   field-permissions matrix, and finding `G02`.

## Open choices

**None.** Two were filed and both were answered by Jan the same day, **A and A**:

- **F09 — does the review loop go on telling a reviewer to review `main`?**
  **A: change the sentence.** A reviewer reviews `claude/dev`; `main` stays where
  it is and means "last released". `docs/review/README.md`'s Branches table and
  `docs/review/PROMPT.md`'s checkout block are changed, and three things went in
  with the sentence because each was a way the loop could still mislead: the
  cycle diagram now says a fixer answers the file on `claude/dev` so `main`'s
  copy keeps the original statuses; both files record that `main` and
  `claude/dev` share **no merge base**, so the eventual merge needs
  `--allow-unrelated-histories` and a reviewer must not attempt it; and
  `PROMPT.md` uses `git checkout -B claude/dev origin/claude/dev` rather than
  `pull --ff-only`, which aborts when a fresh container's local branch is itself
  unrelated to the remote — as it was here. Option **B**, merging into `main`,
  is kept for when a release is due.
- **F08 — should the deleted `.codex/` scripts come back?** **A: leave them
  deleted.** `dev/` is the only supported path and `dev/README.md` says so.
  `git log -- .codex` recovers them if that ever changes.

One thing this session decided rather than deferred, and it is user-visible, so
it is called out here as well as in the ledger: **a matrix save where every cell
was left at "(No change)" no longer says *Successful update***. Redmine core does
say it there. The alternative the finding literally asked for — say nothing at
all — leaves somebody who pressed Save with no feedback, which is worse than
either wrong message, so the new message covers both causes in one sentence:
nothing was changed, or nothing submitted was accepted. Reversible by deleting
one locale key and one branch.

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

# one spec file only (dev/run.sh always runs the whole directory)
dev/sync.sh .redmine/7.0-stable-postgresql
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rspec \
  plugins/redmine_project_workflows/spec/controllers/project_workflows_controller_spec.rb)

# the JavaScript gate the suite cannot run (node only, not in CI)
node dev/check-bulk-js.mjs

# lint (rubocop's binaries are not on PATH by default in this container)
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle install
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant.

## Known traps

Everything below cost time at least once. The first group is new this session;
the rest is carried forward.

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
  this session the C01 view fix once: writing the old version over the file,
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
- **PostgreSQL will not cast a text literal to a timestamp inside a `SELECT`
  list.** The backfill uses `CURRENT_TIMESTAMP`.
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


## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

There is no WP9, the plan is finished, the review round of 2026-08-27 is closed,
and CI is green on the head. So the honest answer to "carry on" is that the
branch is waiting on Jan — say so rather than inventing work. The "Exact next
step" section above lists what he could ask for next.
