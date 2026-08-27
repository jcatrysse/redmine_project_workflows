# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP8** are done and have been for seven
  sessions. `docs/implementation-plan.md` runs WP0..WP8 and every row reads
  *done*. There is no WP9. What happens now is the **review loop** in
  `docs/review/`.
- **This session was the fixer** on `docs/review/findings/2026-08-27-bundled-followup.md`
  — a review of what the *previous* fixing session did with the twenty findings
  of `2026-08-27-bundled.md`. Four findings, no blocker and no major: two minor,
  two nits.
- **All four are answered: three `fixed`, one `invalid`.** No findings file
  anywhere has an open finding — `grep -rn '^- \*\*Status:\*\* open'
  docs/review/findings/` matches only `TEMPLATE.md`.
- **The `invalid` one is worth knowing about before reading anything else.**
  F03 said F10 of the previous run had silently dropped one of its own
  sub-items. It had not: F10's `Resolution:` carries a paragraph declining that
  sub-item explicitly, it was present at `9ce1921` (the commit the review
  examined), and `git log -S` names the commit that added it. So the previous
  run's findings file was **not** edited, and what survives of F03 is a habit
  rather than a repair — see the traps.
- **Two of the three fixes repaired defects the previous round introduced**,
  which is what that review existed to find: F01 (a refused-value count
  multiplied by the size of the selection) came from the fix for F06, and F04
  (a log line reading the raw parameter) from the fix for F19. F02, the guard
  that raised on an array payload, was pre-existing and had been moved unchanged
  into a new file.
- **What exists:** the plugin at **0.1.5**, still unreleased — `main` carries
  0.0.3 and there is no tag. This session **did not bump the version**: the four
  fixes went into 0.1.5's existing `CHANGELOG.md` entry, which now covers both
  rounds, so `init.rb` and the newest changelog heading still agree (there is a
  spec that asserts they do). A version whose only difference from another one
  nobody has run is not worth minting.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started there
  already in sync (`--is-ancestor` clean), which is the first time no branch
  rescue was needed. Four commits, each pushed and verified with
  `git ls-remote --heads origin`.
- **`main`:** untouched. Jan asks for the merge himself, and the two histories
  are still **unrelated** — no merge base, so a merge needs
  `--allow-unrelated-histories`. `main` also still carries the old two-cell CI.
- **Open choices for Jan:** **one**, filed this session and not urgent — what
  the refused-values count should mean (F01). The safest reversible default is
  implemented; the alternative costs eight locale files. See *Open choices*.

## What this session produced

Four commits: one per minor finding, then the two nits together, then the
memory files.

### F01 — one refused value reported itself once per project (minor)

`MatrixSaveResult` carries three counts, and the two administration actions write
one **population** per selected project (`Generic`, then each project) and sum the
results. `written` and `skipped` count *combinations*, so summing is right.
`rejected` counts *submitted values* — and there is one submission however many
populations it reaches, so summing it multiplied one bad value by the size of the
selection. One unacceptable value with "all projects" selected on a
five-hundred-project installation told the operator that five hundred values were
refused and five hundred rules left unchanged. **That is the defect class F06 was
filed for, inside the sentence F06 added.**

`#+` now sums two members and takes the **maximum** of the third. Not the two
shapes the finding sketched: counting outside the per-population loop duplicates
the whitelist outside the writer (the "one rule in two places" mistake this
repository has had four findings about), and dividing by the number of
populations needs a denominator `#+` does not have and would round. The maximum
is exact for the shape that exists — both whitelists are built from
installation-wide lists, so every population refuses the same leaves — and it
degrades to "the most any one population refused" rather than to a product if
that ever changes.

**Two existing assertions were wrong and were corrected.** Saying that out loud
is required by `docs/review/README.md` rule 2, because a diff stat cannot tell a
correction from a weakening. Both demanded `count: 2` for a request carrying one
bad value, and one of them *explained* the 2 in its own comment as "one rejected
leaf per project of the selection" — the defect written down as the
specification. A third assertion elsewhere in the same file was already correct
at `count: 1` and is untouched; it is what made the other two look plausible.

### F02 — the guard against a 500 raised a 500 (minor)

Both `to_plain_hash` copies asked `respond_to?(:to_h)`. `Array` answers yes and
then raises — `['x'].to_h` is `TypeError: wrong element type String at 0` — so
`?transitions[]=x` produced a 500 from inside the method whose entire purpose is
to turn a malformed matrix into a polite rejection, on all four save entry
points. Both now ask what the value **is**, which is the question the loops one
level down already ask. Two edits rather than one shared method, because the
divergence F14 recorded is still real.

The finding also asked for a decision about a Hash whose **keys are not
Strings**, the other shape Rails can produce. Decided: the writers accept any key
answering `to_s` and `to_i` and normalise what survives the whitelist to Strings;
the controller guards do not coerce keys, because the path that can carry
non-String keys — core's own `replace_transitions`, routed through the writer for
INV-1 — never passes through them. Symbol keys were not merely untested but a
**live 500**: they passed the whitelist (`:"1".to_s` is `"1"`) and then reached
`Symbol#to_i`, which does not exist.

### F04 — one log line, one word (nit)

`params[:rule_type]` → `@rule_type`. Nothing behaved differently: the
`before_action` renders 404 for anything else, which is exactly why **no test was
added** — an example asserting the log names `transitions` passes identically
before and after, and one reaching the log with a third value cannot exist. The
`Resolution:` says so rather than inventing a test that restates the guard.

## What the work found that the findings had not

- **F03's premise was false, and only `git show` on the reviewed commit could
  establish that** rather than a fixer's memory of his own previous session. The
  paragraph the finding says is missing is the sixth of seven in a long
  `Resolution:`.
- **Symbol keys were a live 500, not a hypothetical.** The finding raised
  non-String keys as "worth thinking about at the same time"; thinking about it
  turned up a path where the whitelist *accepts* a payload and the writer then
  raises on it two methods later. Integer keys, which look like the same case,
  already worked — every comparison downstream is `.to_s` or `.to_i`.
- **The array payload is only dangerous at the top level.** `?permissions[1][]=x`
  was already safe, because every nested level tests `is_a?(Hash)` or
  `respond_to?(:each)`. So the fix is one line in each guard and not a recursive
  sweep — established by running all five shapes rather than by reading.
- **`Array#to_h` is the trap, not `Array#respond_to?(:to_h)`.** A guard written
  as a capability check reads as careful and is not: `respond_to?` is true of the
  exact class that breaks it. This is the third finding in three runs whose whole
  content is a check that asks the wrong question about a value.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 7.0-stable + PostgreSQL 16 | **735 examples, 0 failures** (was 722; thirteen added) |
| Plugin suite, 5.1-stable + PostgreSQL 16 | **735 examples, 0 failures** |
| Plugin suite, 6.1-stable + PostgreSQL 16 | **735 examples, 0 failures**, on a host built after the four commits had landed — **three** of the nine cells were exercised locally, and 6.1 is where a `Symbol#to_i` or an `Array#to_h` would behave differently only if Ruby did |
| Red on the old code | **eleven of the thirteen**, run per commit against the code as it stood. F01: six (two corrected assertions, one new four-population controller example that reported **4**, three struct examples where the five-hundred-population case reported **500**). F02: five (four array-payload examples failing with the `TypeError` itself, and the symbol-key example with `NoMethodError: undefined method 'to_i' for an instance of Symbol`). The other two — integer keys, and the leaf count of a non-String-keyed payload — passed before and exist so the decision is stated in both directions |
| Reproduced before fixing | F02's five payload shapes re-run against both guards in plain Ruby: the finding's table reproduces exactly. F01's multiplication read off the summation and then demonstrated by the failing examples above |
| Migrations up → 0 → up | **clean on all three hosts** — on 5.1 and 7.0 run BEFORE the suite touched either, on 6.1 on a host built afterwards — after `VERSION=0`: leftover columns `[]`, plugin tables `[]`, plugin rows in `schema_migrations` `[]`; after the re-migrate: both back |
| RuboCop | **105 files, no offences**, through `.github/lint/Gemfile`, and **no** `.rubocop.yml` or `.rubocop_todo.yml` change — one new spec file absorbed without relaxing a cop. No `Metrics` limit was crossed, so nothing needed extracting this time |
| JavaScript gate | **34 checks pass** (`node dev/check-bulk-js.mjs`) |
| Locale files | **untouched.** F01's option A was chosen partly so that they would be |
| Version gate | `init.rb` 0.1.5 = the newest `CHANGELOG.md` heading, which now covers both rounds |
| MySQL, MariaDB | **not run locally** — no server in this container. CI covers six of the nine cells |
| CI | run **115** on `efc799d`, this session's head: **green on all eleven jobs** — nine matrix cells, RuboCop, the bulk-action JavaScript gate. Run **111** was green on the F01 commit; runs 112, 113 and 114 read `cancelled`, which is the concurrency group superseding them rather than a failure. Run 109 was the green on `9ce1921`, the commit this review examined |

## Exact next step

1. **Read CI for the head.** Nothing in this session is adapter-sensitive — no
   migration changed, no SQL changed, the only shipped-code changes are two
   guards, one struct method and one variable — but the rule is to read it
   rather than to reason about it.
2. **Then it is Jan's turn.** Every finding in every findings file is closed or
   decided. The readable account for a user is `CHANGELOG.md`'s 0.1.5 entry,
   which now covers both rounds; the readable account for a maintainer is the two
   findings files.
3. **One choice is waiting** and it is not blocking: F01's wording (below).
4. **If a next session is asked to keep going anyway**: a fresh review run is the
   only honest option, and it would be the third on the same code. Do **not**
   invent a WP9, and do **not** re-open the previous run's "Checked and not
   filed" table — 24 claims, thirteen rejected or already decided, four of them
   by Jan on 2026-08-27 with an explicit instruction not to re-open them.

## Open choices

**One**, filed 2026-08-27 by this session. Full options in `docs/DECISIONS.md`
under *Open — for Jan*; the short form:

- **F01 — what should the refused-values count count?** **A)** the values in the
  request, whatever the selection was resolved into — **implemented**, one line
  in `MatrixSaveResult#+`, and no locale file changes. **B)** keep the total and
  reword the sentence to name refusals across the selection — nothing changes in
  code, and it needs a new phrasing in **eight** locale files, six of which would
  be unreviewed translation presented as translation; it also asks the operator
  to care how many populations a selection resolved into. **Recommendation: A**,
  which is in place. **Not urgent** — reachable only through a hand-built request
  or an API client either way.

And still standing from before, because a later session must not undo them:

- **G02 — a bulk tracker change spanning many projects asks twice per project.**
  **Answered by Jan on 2026-08-27: `A for now, B if it becomes an issue later`.**
  Left as it is; when it is ever felt, the fix is **B** (resolve the whole
  `edited_issues` set in one call, which means patching `IssuesController`), and
  **not** the half measure C. Status `wont-fix for now`.
- **F21 — no event log for scope changes. Answered `A` by Jan on 2026-08-27.**
  `created_by` and `updated_by` are the whole audit story. **A later session must
  not add an event-log table on the grounds that the audit trail is thin: it is
  thin on purpose.** F19's per-write log line is an *operational* record, not an
  audit trail.

## Development environment (rebuild from scratch in a fresh session)

```bash
# packages the container does not have
apt-get update -qq && apt-get install -y rsync libpq-dev

# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (about two minutes each; run them in the
# background in parallel). Two are enough for ordinary work; build the third
# when a change touches a method in F03's digest table, which is measured per
# Redmine minor.
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/setup.sh 7.0-stable postgresql 3.3.6
dev/setup.sh 6.1-stable postgresql 3.3.6

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
RUBY_VERSION=3.2.6 dev/run.sh .redmine/5.1-stable-postgresql

# one spec file only (dev/run.sh always runs the whole directory)
dev/sync.sh .redmine/7.0-stable-postgresql
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rspec \
  plugins/redmine_project_workflows/spec/services/matrix_save_result_spec.rb)

# what a guard or a service actually does to a value, without Rails in the way:
# plain ruby against a reproduction of the method is how F02 was established
/opt/rbenv/versions/3.3.6/bin/ruby -e '...'

# regenerate F03's digest table for one host (do this ONLY after deciding the
# plugin's copy must follow core's change -- never before)
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rails runner \
  'RedmineProjectWorkflows::Services::CoreMethodDigest.digests.sort.each { |k, v| puts "  %s: %p" % [k.inspect, v] }')

# the JavaScript gate (also a CI job)
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

- **`respond_to?` is the wrong question to ask a value whose type is the
  problem.** `Array` responds to `to_h` and raises when you call it. A guard
  written as a capability check reads as careful and is not: ask `is_a?(Hash)`.
  The same shape has now produced three findings in three runs — a check that
  asks something adjacent to what it needs to know.
- **A sub-item's answer should open with the sub-item's subject.** F10's
  declination of its own last sub-item is written down in full, and a careful
  reviewer still filed a finding saying it was missing — because it is the sixth
  paragraph of seven and opens with "The one thing I did not do". Findable by
  reading to the end is not findable by grep. (And before believing such a
  finding: `git show <reviewed-commit>:<file>`, because the fixer's memory of his
  own previous session is the least trustworthy source in the room.)
- **A count that is summed across populations has to be a count *of* something
  per population.** `written` and `skipped` count combinations and add;
  `rejected` counts submitted values and must not. Whenever a struct is combined
  with `sum`, ask that question of every member — the multiplication is invisible
  in a diff and a spec had encoded it as though it were the requirement.
- **A spec comment that explains a number is where a wrong number hides.** The
  assertion that locked F01 in came with a comment deriving the multiplied count
  from the selection — so the suite documented the defect as the specification,
  and reading the comment was more misleading than reading the assertion alone.
- **A `cd` into a host checkout turns the next `git push` into a push at
  *Redmine*.** The working directory persists between tool calls, and a
  `git add -A && git commit && git push` typed after one committed a copy of the
  plugin into `.redmine/6.1-stable-postgresql` and then tried to push it to
  `github.com/redmine/redmine`, which refused it — the only reason nothing was
  lost. This trap was already in the list twice, in its milder forms; this is
  what it looks like at full strength. Prefix every command that writes anything
  with `cd /home/user/redmine_project_workflows &&`, or use `git -C <path>`.
- **`Symbol#to_i` does not exist.** A payload whose keys are Symbols passes a
  whitelist built on `.to_s` and then dies in code built on `.to_i`. If two
  methods normalise a key differently, one of them is a 500 waiting for a caller
  that is not a web request.

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

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

There is no WP9 and the plan is finished, so "carry on" means the review loop —
and the loop is **empty of work** again. In order:

1. **Read CI for the head** and act on it if it is red. Nothing this session
   touched is adapter-sensitive, but reading beats reasoning.
2. **Nothing else is waiting.** Twenty-four findings across the two 2026-08-27
   files are closed, decided, or `invalid`, each with a `Resolution:` line. One
   choice is with Jan (F01's wording) and its default is implemented.
3. **If more work is wanted rather than needed**, a fresh **review run** against
   the current head is the only honest option — and it would be the third review
   of the same code, so expect its yield to be low and its false-positive rate to
   be higher: this run filed four findings and one of the four was wrong about a
   file it had read. A reviewer should check a "this was not answered" claim
   against the reviewed commit before filing it.

Do not invent a work package, and do not re-open the previous run's "Checked and
not filed" table: 24 claims, thirteen rejected or already decided, four of them
by Jan on 2026-08-27 with an explicit instruction not to re-open them.
