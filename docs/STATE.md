# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP8** are done and have been for five
  sessions. `docs/implementation-plan.md` runs WP0..WP8 and every row reads
  *done*. There is no WP9. What happens now is the **review loop** in
  `docs/review/`.
- **This session was the fixer** on `docs/review/findings/2026-08-27-bundled.md`
  — a review that bundled *three* independent reviews of `03a1ab0` and
  re-verified every claim in them, filing 21 findings.
- **Nineteen of the 21 are `fixed`. One is `open` on purpose (F11) and one is a
  question for Jan (F21).** Both carry a `Resolution:` line saying why, so
  nothing in that file is silent. Every one of the 19 also carries a
  `Resolution:` line saying what was done, how it was verified, and — where it
  happened — what the writing of the test found that the finding had not said.
- **What exists:** the plugin at **0.1.4**. 0.1.0 is the scope model and the
  eight work packages; 0.1.1 the two matrix-save repairs; 0.1.2 the two
  concurrency repairs; 0.1.3 one operability defect and seven edges; 0.1.4 is
  this session.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/review-findings-2026-08-27-aeun9v`, which the environment minted, and
  moved to `claude/dev` immediately, as the pin requires. Nine commits, each
  pushed and verified with `git ls-remote --heads origin`.
- **`main`:** untouched by this session. Jan asks for the merge himself. Two
  things still true from last session: `main` carries the *old* two-cell CI while
  the ten-job `specs.yml` exists only on `claude/dev`, and `origin/main`'s
  history is **unrelated** to `origin/claude/dev`'s — they share no merge base,
  so the merge needs `--allow-unrelated-histories` or a deliberate replacement of
  `main`'s tree.
- **Open findings across the whole repository:** **two**. `F11` in this run's
  file, and `G02` (the batching pass for a cross-project bulk tracker change) in
  `docs/review/findings/2026-08-26-wp2-observations.md`. Check with
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/`.
- **`spec/characterization/`:** still **gone**, since WP3.
- **Open choices for Jan:** **one**, and it is F21, which was filed as a question
  by the reviewer and was never a fixer's to answer. See "Open choices" below.

## What this session produced

Nine commits, one per group of findings, in the order the fixer prompt set. The
two majors first.

### F01 — the copy screen wrote rules before it locked the scope table (major)

The defect 0.1.2 removed from three write paths, still standing on the fourth.
`WorkflowsController#duplicate` wrote `workflows` for every target project and
only then read `project_workflow_scopes` to decide which combinations needed a
scope — check-then-act, on the one path nobody re-checked. `docs/design.md` had
meanwhile recorded "every path therefore takes scope rows before workflow rows",
a universal claim written on the strength of three paths having been changed.

**The quiet outcome was reproduced rather than read**, which the fixer prompt
asked for specifically. Two live connections driven from Rails on 7.0-stable +
PostgreSQL 16, with a scope carrying no rules (the state `clear_rules` leaves):
old code gave `project rules=1  scope exists=false` — one rule in `workflows`
under no scope, invisible to the resolver, no error, "Successful update". With
the lock: `rules=0  scope=false`, a clean return-last-wins.

`ScopeWriter.lock_scopes_for_copy` is now the first statement in the copy's
transaction, over combinations computed by `WorkflowRule.copy_pairs_for_project`
— extracted out of `copy_for_project` so the lock set and the write share **one**
copy of the skip rule. Ascending primary key order, both rule types, so it queues
against `lock_combinations`' three callers rather than deadlocking with them.

### F03 — nothing would have noticed Redmine changing under the plugin (major)

The plugin reimplements core methods rather than extending them, because core's
queries carry no `project_id` predicate and there is no `super` to fall through
to without breaching INV-4. That is right, and its standing cost is that a change
underneath is silent: the plugin's own specs assert the plugin's answers, not
core's. It has already happened twice to `Issue#new_statuses_allowed_to`, both
times semantically.

`spec/upstream/core_drift_spec.rb` + `core_method_digests.yml`, over a new
`Services::CoreMethodDigest`: core's body for every shadowed method, read off the
host through `UnboundMethod#super_method` and `RubyVM::AbstractSyntaxTree.of`,
normalised, digested, compared against a table keyed by Redmine minor. Plus an
**oracle** half — `super_method` binds, so core's implementation is callable, and
four examples assert the plugin agrees with it where nothing is overridden while
one asserts it stops agreeing once a project owns its workflow.

**Eighteen methods, not the eleven the review counted, and discovered at runtime
rather than listed.** The delegates drift too, and two of the copies are private
in core — one of them `Issue#workflow_rule_by_attribute`, which decides which
fields are read-only or required. A first draft used `instance_methods(false)`
alone and silently covered thirteen of fifteen.

The **6.1 host was built for this**, so the table covers all three minors and no
CI cell meets an unmeasured Redmine. Measured: 6.1 and 7.0 identical on all
eighteen; 5.1 differs in exactly three, the controller actions. `requires_redmine`
was **not** narrowed — an out-of-range Redmine then refuses to boot until an
administrator deletes the plugin directory — and an unmeasured minor is therefore
*reported*, not failed.

### The other seventeen

- **F02** `docs/design.md`'s lock-order sentence now names four paths, says why a
  sample became a universal, and states the qualification it really carries.
- **F04** the resolver's hot path is one statement, no join, no `DISTINCT`.
- **F05** the administration matrices do no work before `require_admin` — one
  guard clause in the patched finder, deliberately **not** a scoped
  `prepend_before_action`, which would have *deleted* core's registration.
- **F06** a save the whitelist partly refused now names how many values it
  refused. A third count on `MatrixSaveResult`, and one new locale key
  translated by hand in all eight files.
- **F07** the JavaScript gate is a CI job. **F08** the INV-9 override count is
  asserted. **F15** focus moves to the undo region before the link is hidden.
- **F09** both timestamp writers build the value in Ruby. `CURRENT_TIMESTAMP` is
  UTC only on PostgreSQL.
- **F10** the inventory's cost is documented per mode, with measured figures.
- **F12** the plugin's `Gemfile` names only `deface`. **F13** CI declares
  `permissions: contents: read` and prints the tested Redmine commit.
- **F14** `normalize_permissions_params` deleted after checking all three
  checkouts. **F16** the copy screen's labels are associated. **F17** a save with
  no matrix says nothing was saved.
- **F18** two traps written down: the callback-dedupe one, and INV-4's single
  deliberate exception, with a gate keeping it at one.
- **F19** every workflow write logs one line, through one service that holds the
  "ids and counts only" rule.
- **F20** README says what the migrations cost; migration 003 prints its row
  tally; `docs/design.md` records the COPY-algorithm rebuild.

## What the tests found that the findings had not

Worth its own section, because five of these are the difference between a gate
and the appearance of one.

- **The F03 oracle passed over a deliberately broken plugin — twice over.** No
  fixture role had `consider_workflow?` false, so the two role lists agreed; and
  worse, the examples ran against `Issue.new`, which resolves from core's
  `old_status_id = 0` pseudo-status, so **they were comparing two empty arrays**.
  Only probing the gate found that. Fixed with a saved issue and a role holding
  `view_issues` only; the same reversion now fails `[1, 2, 4]` against `[1, 2]`.
- **A YAML digest of all zeros parsed as an Integer.** Found while probing the
  drift gate with a wrong digest. The table's values are quoted now.
- **The F08 override-name grep found seventeen names for fifteen overrides**, because
  two overrides render form fields whose own markup carries `name:`. Wrong in the
  direction that hides a missing override. Names now come from inside each
  `Deface::Override.new` call.
- **The F04 assertion "no subquery" was the wrong gate** and failed against the
  correct fix: the recommended shape *keeps* an `IN` subquery, because `IN` is
  already a semi-join. What goes is the join, the `DISTINCT`, and the subquery
  selecting `workflows.id` for the join to look the row up again.
- **The F10 assertion "the two query counts are equal" was also wrong.** The
  small selection costs 5 and the large one 3, because a count query is skipped
  when there is nothing to count. The property is a bound, not equality.
- **The F12 assertion `not_to include('rspec-rails')` failed on the file's own
  comment** explaining which gems had been removed. It reads declarations now.
- **The F15 checks, inserted between an existing scenario and the `cells` it
  depended on, broke it** — the exact state leak `dev/check-bulk-js.mjs`'s header
  warns about.
- **F14's finding said "there is no spec".** There were two, asserting that the
  transposed payload *was* accepted. They were **inverted rather than deleted**,
  which says strictly more.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | **717 examples, 0 failures** (was 671; 46 added) |
| Plugin suite, 7.0-stable + PostgreSQL 16 | **717 examples, 0 failures** |
| Plugin suite, 6.1-stable + PostgreSQL 16 | **717 examples, 0 failures** on the final tree. Run because the 6.1 host was built for F03's digest table, so **three** of the nine cells were exercised locally this session rather than the usual two |
| Migrations up → 0 → up | **clean on 5.1 and 7.0**, run **twice** — after F09 changed migration 004 and again after F20 changed migration 003 — each time on a database rebuilt from *core* migrations only (`db/schema.rb` deleted, `db:drop db:create db:migrate`) and **before** the suite touched that host. Leftovers `[]`, plugin rows in `schema_migrations` `[]` |
| `dev/check-backfill.sh` | **green on 5.1 and 7.0** after both migration changes |
| Migration 003's orphan delete | **exercised with an orphan actually present**, which CI has never done: `-> 1 rows`, row gone afterwards. Also confirmed the old `execute` form printed no count at all |
| Fails on the old code | **19 of the 46 new examples**, run rather than assumed, per group against the immediately preceding commit. Each finding's `Resolution:` line names its own count and names the companions that pass on both. Three findings (F19's logging, F03's table, F12's gate) are new-code gates with no old behaviour to be wrong, and say so |
| Gates proved by *firing* | three: the F08 override count (a real sixteenth override added → `expected: 15 got: 16`), the F03 digest (a wrong digest → the method, both digests and core's `source_location` named), and the F03 oracle (core's pre-5.1 role list restored → `[1, 2, 4]` vs `[1, 2]`) |
| RuboCop | **104 files, no offences**, through `.github/lint/Gemfile`, and **no new `.rubocop_todo.yml` entry**. Six `Metrics` limits were crossed and all six fixed by extracting rather than relaxing — see the traps |
| Locale parity | **8 files × 97 keys**, no difference. One key added, translated by hand in all eight |
| JavaScript gate | **34 checks pass** (was 28; F15 added six), and it is **a CI job now** |
| MySQL, MariaDB | **not run locally** — no server in this container. CI covers six of the nine cells |
| CI | **not yet run for this session's commits.** Run 90 was the last known green, on `03a1ab0`, which is the commit the review examined. The nine commits since have not been through CI, so the MySQL and MariaDB cells have seen none of this work — see "Exact next step" |

## Exact next step

1. **Read CI first, and expect it to have something to say.** Nine commits went
   in without CI feedback, and three of them touch things only a MySQL or MariaDB
   cell can judge: F09's `TIMESTAMP '...'` literal (accepted by all three in
   theory, unmeasured on two), F20's migration 003 change on a COPY-algorithm
   rebuild, and F03's digest table, which is measured from PostgreSQL hosts but
   read on all nine. The digest is the one to watch: it is normalised source text
   and should be adapter-independent, but it has never run on a MySQL cell.
2. **Then F11**, the last open finding, with its four steps written into the
   findings file. Step 1 is the important one: write the missing example — two
   projects overriding the same role for the same tracker, with a generic row for
   that role — and confirm it passes on today's code *before* touching
   `generic_conditions`. Grouping without hoisting its cross-pair `excluded` set
   breaches INV-5 while every existing example stays green.
3. **Then it is Jan's turn.** `docs/review/findings/2026-08-27-bundled.md` is the
   readable account of all 21 findings; the CHANGELOG's 0.1.4 entry is the same
   thing for a user.
4. One choice is waiting: **F21**. See below.

## Open choices

**One**, and it was the reviewer's question rather than anything this session
decided.

- **F21 — should scope changes carry an append-only event log?**
  `project_workflow_scopes` records *who* decided a project runs its own workflow
  and *who* last changed the rules. It cannot answer *what* changed, which rules
  disappeared, or through which of the four write paths. Redmine does not audit
  generic workflow changes either — but Redmine also does not delegate workflow
  editing to project members, and this plugin has since WP4.
  - **A)** Leave it. `created_by` and `updated_by` are the whole audit story, and
    the question operators actually ask — how does this project's workflow differ
    from the generic one — already has a screen.
  - **B)** Write ADR-002 for an append-only event log: a table, a retention
    policy, a rule for what happens when a project is deleted, and a position on
    what may be stored.
  - **Recommendation: A**, for now. **F19 landed this session and changes the
    picture without answering the question:** every workflow write now logs one
    line with the actor, the ids and the counts. That is an *operational* record —
    not queryable, not retained on a policy, not attached to the project — so it
    makes "what did that request do" answerable to somebody with log access and
    leaves "who removed this transition, and when" exactly as unanswerable. If
    that second question is one Jan expects to be asked, it is B and it is an ADR.
  - **Urgent?** no. Nothing is blocked on it.

One thing this session decided rather than repaired, called out here as well as in
the ledger because it is user-visible: **a shipped migration was changed.** F09's
timestamp fix went into migration 004 as well as into the live code path. An
installation that has already migrated keeps the values it wrote — they are not
displayed anywhere, so this is invisible — and one migrating from now on gets
correct ones. The alternative was to fix only the live path and knowingly ship a
statement already diagnosed as wrong.

## Development environment (rebuild from scratch in a fresh session)

```bash
# packages the container does not have
apt-get update -qq && apt-get install -y rsync libpq-dev

# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (about four minutes each; run them in
# the background in parallel). All three are worth building now: F03's digest
# table is measured per Redmine minor, so a change to a copied method has to be
# re-measured on each.
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/setup.sh 6.1-stable postgresql 3.3.6
dev/setup.sh 7.0-stable postgresql 3.3.6

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

# sync the working tree and run the suite
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-postgresql

# one spec file only (dev/run.sh always runs the whole directory)
dev/sync.sh .redmine/7.0-stable-postgresql
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rspec \
  plugins/redmine_project_workflows/spec/upstream/core_drift_spec.rb)

# regenerate F03's digest table for one host (do this ONLY after deciding the
# plugin's copy must follow core's change -- never before)
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rails runner \
  'RedmineProjectWorkflows::Services::CoreMethodDigest.digests.sort.each { |k, v| puts "  %s: %p" % [k.inspect, v] }')

# the JavaScript gate (also a CI job now)
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

- **A gate that has never fired is a claim about nothing, and only a probe tells
  you which kind you have.** Three gates were built this session and all three
  were *deliberately made to fail* before being trusted. Two of the three were
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
- **Six `Metrics` limits were crossed this session and all six were fixed by
  extracting.** They are already relaxed in `.rubocop.yml` with a stated
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


## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

There is no WP9 and the plan is finished, so "carry on" means the review loop.
Two things are genuinely waiting, in this order, and neither is invented work:

1. **CI has not run on any of this session's nine commits.** Run 90 was the last
   known green, on the commit the review examined. Read the run for the head
   before anything else — three changes can only be judged by a MySQL or MariaDB
   cell, and `docs/STATE.md`'s "Exact next step" says which.
2. **F11 is the one open finding**, with its four steps written into
   `docs/review/findings/2026-08-27-bundled.md`. Do step 1 first: it is the
   example that makes the rest safe, because the obvious fix breaches INV-5 while
   every existing example stays green.

After that the branch is waiting on Jan, and F21 is his to answer.
