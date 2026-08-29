# Review run — 2026-08-28 — Claude Code (Opus), production-readiness audit

- **Reviewer:** Claude Code (Opus 5), in a Claude Code on the web container
- **Commit reviewed:** `e7f1e90` (the head at the time; `c872fe8` landed during
  the write-up and is read into the summary below)
- **Ran the test suite:** yes — a Redmine 5.1-stable host built from scratch in
  this container. **861 examples, 0 failures, 9 pending.** The nine pending are
  the row-locking examples, which skip themselves on an adapter without
  `SELECT … FOR UPDATE`; see F02 for why the adapter was SQLite. RuboCop through
  `.github/lint/Gemfile`: **120 files, no offences**. `node dev/check-bulk-js.mjs`:
  all checks pass. CI run **137** on `e7f1e90`: **11/11 jobs green**, read from
  the Actions API — the full 3 × 3 matrix plus lint and the JavaScript gate, each
  cell also running migration reversibility and a Zeitwerk check.
- **Scope covered:** the whole repository against a general production-readiness
  brief — Redmine integration, Rails correctness, security, data integrity,
  performance, concurrency, frontend, tests, dependency and deployment. Every
  claim the plugin makes about core's behaviour was checked against Redmine
  5.1-stable and 7.0-stable source fetched during the run: callback order in
  `WorkflowsController`, the fifteen Deface anchors, `WorkflowsHelper`'s emitted
  parameter shape, `dependent:` associations on `Tracker` / `Role` / `IssueStatus`,
  `Project#rolled_up_trackers_base_scope`, `AccessControl.read_action?`,
  `rails-ujs` on 7.0, and the sprite icon ids.
- **Scope NOT covered:** only Redmine 5.1 was built locally, and on SQLite rather
  than a supported adapter (F02 is why), so cross-database and cross-version
  claims rest on CI run 137 rather than on a local cell. No browser was driven.
  The six non-authoritative locales were checked for key parity and for strings
  identical to English, which is not a translation review. No upgrade rehearsal
  from an older release of this plugin. **This run did not install a single
  neighbouring plugin** — `2026-08-28-claude-plugin-compat-5.1.md`, which landed
  the same day, is the run that did, and its F01 is more serious than anything
  here.

## Summary

I went looking for the failure modes a largely AI-written plugin usually has —
invented Redmine APIs, missing authorization, request parameters reaching
queries, N+1s, abstractions with no purpose — and found essentially none of
them. Authorization is correct at every entry point I could construct a request
for, and correct *by construction* rather than by inspection: the project comes
from the path, and the tracker and role are resolved by intersecting the
parameter with a list the server built from that project. I could not find a
security defect.

What I did find is a small number of specific things, of which two matter. The
plugin prepends `WorkflowsHelper`, which is exactly the construct its own
forbidden-constructs table bans for `ProjectsHelper`, and I reproduced the
failure: a neighbouring plugin using the ordinary 2013-era `alias_method` chain
turns the administration workflow screens into a `NoMethodError` for both
plugins (F01). None of the forty-four plugins on Jan's own stack does this
today, so it is a latent risk for a wider audience rather than a live one for
him. And deleting an issue status can silently turn a project's own workflow
into an *empty* one — deny-all, no status control on the form, nothing said
anywhere (F03). I reproduced that too.

The rest are smaller: a non-portable SQL literal that aborts installation
half-way on SQLite (F02), a validator that raises instead of rejecting on a
malformed payload (F04), a request contract the code contradicts (F05, found by
a ChatGPT review Jan commissioned in parallel and confirmed here), and three
core methods the drift gate does not watch — including the two the whole INV-1
routing rests on (F06).

The positive result is worth stating as plainly as the findings. The scope table
is the right central decision and everything follows from it consistently.
`WorkflowPopulations` makes INV-4 structural rather than disciplinary — a
relation on `workflows` without a `project_id` cannot be built there. The
conventions spec turns the invariants into executable gates, and the drift spec
digests core's own method bodies *and* runs oracle examples against them. That
combination is rarer than it should be and it is the reason this audit could be
about six real things rather than about whether the code means what it says.

**Counts:** blocker 0 · major 2 · minor 5 · nit 4 · question 0

---

### F01 — Prepending `WorkflowsHelper` breaks, and is broken by, a neighbour's alias chain — the plugin's own forbidden construct

- **Status:** fixed
- **Severity:** major
- **Confidence:** confirmed
- **Category:** portability
- **Where:** `lib/redmine_project_workflows.rb:79` (`prepend_once(WorkflowsHelper, …)`),
  `lib/redmine_project_workflows/patches/workflows_helper_patch.rb:10-16`
- **Invariant touched:** none — but it is the forbidden-constructs row in
  `CLAUDE.md` that reads "a prepend on any core helper other plugins alias-chain"

**What is wrong**

`CLAUDE.md` bans `ProjectsHelper.prepend` and, in the same row, "a prepend on any
core helper other plugins alias-chain". `Patches::ProjectsHelperPatch#apply!`
explains the mechanism at length and uses `ProjectsController.helper(Mod)`
instead. `WorkflowsHelper` is a core helper, the plugin prepends into it, and
`options_for_workflow_select` — one of the three methods it puts there — calls
`super`.

`alias_method` resolves through `WorkflowsHelper.ancestors`, which with a prepend
in place *starts* at the prepended module. A neighbour therefore copies the
plugin's method into its `_without_` alias, and that copy's `super` looks above
`WorkflowsHelper`, where core's own method no longer is.

**Why it matters**

Administration → Workflow — both matrices, the copy screen, and the project
matrices, which render core's `workflows/_form` — raises `NoMethodError` for
every administrator. Both plugins break, not only the neighbour, and load order
does not help: plugins load alphabetically and the trap fires whichever runs
second.

There is a second, silent variant. `transition_tag` and `field_permission_tag`
are full replacements with no `super`, so a neighbour that alias-chains *those*
is quietly disabled — its redefinition lands on `WorkflowsHelper` itself, below
the prepended module, and never runs.

**How I verified it**

On the running 5.1 host, simulating the ordinary neighbour idiom
(`alias_method :x_without_y, :x` … `alias_method :x, :x_with_y`) applied to
`WorkflowsHelper` after this plugin had loaded:

```
WorkflowsHelper ancestors: [RedmineProjectWorkflows::Patches::WorkflowsHelperPatch,
                            RedmineProjectWorkflows::BulkActionsHelper,
                            RedmineProjectWorkflows::VersionHelper]
call FAILED: NoMethodError: super: no superclass method `options_for_workflow_select'
```

Calibration, because it changes the priority: I searched
`2026-08-28-claude-plugin-compat-5.1.md` for `WorkflowsHelper` and found nothing,
so **none of the forty-four plugins on Jan's own stack triggers this today**. It
is a live risk for a public release and a latent one for his pilot.

**Suggested direction**

The same move `ProjectsHelperPatch` already makes: attach to the helper chains of
`WorkflowsController` and `ProjectWorkflowsController` rather than to
`WorkflowsHelper`. Note that ADR-003's owned administration screens dissolve this
finding entirely — `options_for_workflow_select` stops being overridden at all —
so the fixing session should decide whether to do the small move now as a stopgap
or fold it into that work.

**Resolution:** fixed. `Patches::WorkflowsHelperPatch.apply!` puts the module
into the helper chains of **both** controllers that render the matrices --
`WorkflowsController` for the administration screens and
`ProjectWorkflowsController`, which renders core's own `workflows/_form` for the
project ones -- and `apply_patches` no longer prepends it to `WorkflowsHelper`.
The reasoning is written into `apply!`, beside the one `ProjectsHelperPatch`
already carries.

Two consequences that were not obvious and are worth the next reader's time.
`CoreMethodDigest` reached core's body through `super_method`, which answers nil
once the patch is no longer in the owner's ancestors, so the three
`WorkflowsHelper#*` digests would have silently vanished from the gate; it now
asks which of the two attachment styles is in use and takes the method itself
where the patch is not prepended. And `spec/helpers/workflows_helper_spec.rb`
had no need to arrange anything, because the patch was *inside* the helper; it
now prepends it to the helper object, which is the position `controller.helper`
produces.

Red on the old code, measured rather than reasoned -- and the first version of
the spec was **wrong**: it copied `WorkflowsHelper`'s own definition by walking
`super_method` down to it, which models a neighbour loading *before* this plugin,
the safe order. With the prepend restored, exactly one of five examples failed.
Rewritten to use a plain `alias_method`, which is what a neighbour loading after
us does, the prepend gives:

```
ActionView::Template::Error:
  super: no superclass method `options_for_workflow_select' for #<ActionView::Base>
  .../patches/workflows_helper_patch.rb:64:in `options_for_workflow_select'
```

three of five red, including both behavioural examples. That near-miss is
recorded in the spec's own comment.

---

### F02 — Three raw-SQL sites use `TIMESTAMP 'literal'`, which aborts installation half-way on SQLite

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** portability
- **Where:** `db/migrate/004_create_project_workflow_scopes.rb:88`,
  `lib/redmine_project_workflows/services/scope_copier.rb:95`,
  `lib/redmine_project_workflows/services/project_workflow_copier.rb:100`
- **Invariant touched:** INV-8, in effect — the installation is left half-migrated

**What is wrong**

All three build `now = "TIMESTAMP #{connection.quote(connection.quoted_date(…))}"`.
The SQL-standard type-keyword form is accepted by PostgreSQL, MySQL and MariaDB,
but SQLite has no `TIMESTAMP` keyword and parses it as a column reference.
Redmine ships SQLite3 support — `config/database.yml.example:55` and a
`sqlite3` branch in its own `Gemfile` — and nothing in this plugin declares it
unsupported. The README's compatibility section says which databases *CI runs*,
which is a different claim.

**Why it matters**

An administrator on a SQLite Redmine follows the README and gets a failed rake
task. Migrations 001–003 have committed by then, so the installation carries
`workflows.project_id`, four indexes and a foreign key with no
`project_workflow_scopes` table — and the resolver queries that table on every
issue form, so restarting Redmine produces a 500 on every issue page until the
plugin directory is removed *and* the migrations reversed.

**How I verified it**

```
== 4 CreateProjectWorkflowScopes: migrating ===
-- Backfilling transitions scopes
rake aborted!
SQLite3::SQLException: no such column: TIMESTAMP
```

Replacing the three literals with the plain
`connection.quote(connection.quoted_date(Time.now.utc))` form — which migration
004's own comment records as measuring correctly on PostgreSQL 16 — makes the
migrations complete and **the whole suite pass on SQLite: 861 examples, 0
failures**. The incompatibility is therefore accidental rather than structural.

**Suggested direction**

Either make the literal portable in all three places, which costs three lines and
gains a database, or decide SQLite is out of scope and refuse it in migration 001
*before* any DDL runs, with a message that says so. What should not survive is a
half-applied schema as the failure mode.

**Resolution:** fixed. All three sites build the literal plain --
`connection.quote(connection.quoted_date(Time.now.utc))` -- and the comments that
argued for the type-keyword form now say why it went. `spec/plugin_conventions_spec.rb`
greps for the construct so it cannot come back; that example is red on the old
code, naming `db/migrate/004_create_project_workflow_scopes.rb`.

**The first fix was wrong, and CI caught it in four minutes.** Dropping the
keyword alone turned all three PostgreSQL cells red at *migration* time:

```
PG::DatatypeMismatch: column "created_at" is of type timestamp without
time zone but expression is of type text
```

Measured afterwards on PostgreSQL 16 rather than reasoned about: a bare literal
in a **plain** select list is coerced against the target column, and under
**DISTINCT** it is not — DISTINCT has to type the column to compare it, so
`unknown` resolves to `text` before the INSERT sees it. The comment that stood in
migration 004 claimed PostgreSQL coerces it; that measurement was right about the
statement it ran and wrong about this one. Both facts are now in the migration's
own comment.

The repair needs no adapter conditional: the DISTINCT moved into a subquery and
the constants stayed in the outer, plain select list. The two services were
already plain SELECTs and keep the bare literal, with the narrow rule written
beside each — *never put an untyped literal in the select list of a DISTINCT, a
UNION or a GROUP BY*. A second conventions example greps for that, and it too was
wrong at first: its comment stripper deleted any line beginning with `#`, which
is exactly what a heredoc line opening `\#{now}` looks like, so it came back
green against the shape it forbids. `#(?!\{)` is the correction, and the
red-check is what found it.

The generated statements were then run against a real PostgreSQL 16 before
pushing — the migration's, with two duplicate rows so DISTINCT had work to do,
and the copiers' — and both insert with the timestamp intact.

Evidence beyond the greps, on SQLite, which is the adapter the finding is about:
migrations from an empty database run clean, `VERSION=0` leaves `leftover
columns: []`, `plugin tables: []`, `plugin schema_migrations rows: []`, and up
again is clean (INV-8). `dev/check-backfill.sh` passes, and it is the check that
matters most here because it asserts the timestamps are **UTC** — the property
the type-keyword form existed to make explicit, preserved by the plain literal.
The whole suite then runs on SQLite: 890 examples, 0 failures.

---

### F03 — Deleting an issue status can silently turn a project's own workflow into an empty one

- **Status:** open
- **Severity:** major
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** the interaction between `ProjectWorkflowScope`'s lifetime and core's
  `IssueStatus#delete_workflow_rules` (`app/models/issue_status.rb:125-126` in
  core)
- **Invariant touched:** INV-3 — the three states stay distinguishable in the
  database, but a deletion moves a project between two of them with nothing said

**What is wrong**

Core deletes every workflow row naming a status being destroyed, across both
populations and with no `project_id` predicate. That is core's business and it is
right. But the plugin's *scope* row survives, and a scope with no rules is
defined as an own **empty** workflow — which for transitions permits nothing at
all. A status deletion can therefore move a project from "own workflow with N
transitions" to "deny everything".

**Why it matters**

Members of that project can no longer change any issue's status for that role,
and nothing on the issue form says why: `new_statuses_allowed_to` returns an
empty list, which is exactly the state the README describes as producing "no
status control on the form whatsoever". Core's `check_integrity` blocks deleting
a status *used by issues*, so it does not protect here — a status used only in
workflows deletes freely. An administrator tidying up unused statuses can freeze
a project's issues.

Without this plugin the same deletion removes generic rules, which usually leaves
other rules standing. The difference is the surviving scope, and it is the
plugin's.

**How I verified it**

On the running 5.1 host: a project with an own transitions scope whose only rule
named status `Zzz-temp`, then that status destroyed through core's own `#destroy`:

```
before: scope=true own_rules=1
  allowed statuses for the member: ["New", "Zzz-temp"]
destroy 'Zzz-temp': ok
after:  scope=true own_rules=0
  allowed statuses for the member: []
```

**Suggested direction**

Two shapes, and the choice matters. *Warn*: count the project scopes a deletion
would empty and say so on the issue-statuses administration screen. *Clean up*:
delete the scope when the deletion empties it, returning the combination to
inheritance. I lean to warning, because deleting the scope collapses two of
INV-3's three meanings on the plugin's behalf, and INV-3 exists to keep them
apart — but the fixing session owns the design.

**Resolution:**

---

### F04 — The `respond_to?(:to_h)` defect fixed in both `to_plain_hash` methods still stands in both writers

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `lib/redmine_project_workflows/services/transition_writer.rb:161-170`
  (`to_hash`), `lib/redmine_project_workflows/services/permission_writer.rb:169-178`
  (`normalize_payload`)
- **Invariant touched:** INV-2 in spirit — the writer is the validation, and a
  validator that raises has not rejected

**What is wrong**

`MatrixParams#to_plain_hash` and `WorkflowsControllerPatch#to_plain_hash` both
carry a long comment explaining that `respond_to?(:to_h)` is the wrong question,
because `Array` answers it yes and then raises `TypeError`, and both were changed
to ask `is_a?(Hash)`. The two writers still ask the old question.

**Why it matters**

Not reachable over HTTP: I traced both controller paths and both guard with the
fixed `to_plain_hash` first. It is reachable through
`WorkflowTransition.replace_transitions` and `WorkflowPermission.replace_permissions`,
which are public core APIs this plugin now owns under INV-1 — so a neighbouring
plugin, a rake task or a console session that passes a malformed payload gets a
raw `TypeError` from inside the plugin instead of the rejection the writer's own
documentation promises.

**How I verified it**

On the running host, through the core APIs:

```
replace_permissions(Array) -> TypeError: wrong element type String at 0 (expected array)
replace_transitions(Array) -> TypeError: wrong element type String at 0 (expected array)
replace_permissions(String) -> NoMethodError: undefined method `each_with_object' for "x":String
```

**Suggested direction**

Ask `is_a?(Hash)` in both and return `MatrixSaveResult.none` for anything else,
mirroring the two methods that were already fixed. The four copies of one rule
are themselves worth looking at.

**Resolution:** fixed. Both writers ask `is_a?(Hash)`, mirroring the two
`to_plain_hash` methods that were corrected first, and a payload that is not a
matrix returns `MatrixSaveResult.none` instead of raising. Eight new examples
across the two writer specs cover an Array, a String and a scalar, and assert
that nothing was written; all eight are red on the old code with
`TypeError: wrong element type String at 0 (expected array)`.

The String case failed differently and is worth naming: `String#sum` exists, so
`leaf_count` answered with a byte checksum and the whitelist raised
`NoMethodError` on `each_with_object` one method later.

---

### F05 — A graph request naming one valid and one invalid role renders the valid one, against its own stated contract

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** spec-conformance
- **Where:** `app/controllers/project_workflows_controller.rb:241-255`
  (`find_tracker_and_roles`) and `:257-285` (`selected_roles`)
- **Invariant touched:** none

**What is wrong**

The comment on `find_tracker_and_roles` says a role the project does not offer
"answers 404 rather than drawing something else: silently narrowing a selection
to what happens to be allowed would draw one workflow under the heading of
another." The implementation narrows silently whenever *something* survives:
`selected_roles` intersects, and the 404 fires only on
`@roles.empty? && @visible_roles.any?`. So `role_id[]=<valid>&role_id[]=999999`
renders the valid role, while `role_id[]=999999` alone answers 404.

**Why it matters**

No unauthorized information is exposed — the invalid value is dropped, not
resolved. The cost is that a stale bookmark or a link generated before a role was
deleted appears to work while showing less than it names, and the screen's
heading claims a selection it did not draw.

**How I verified it**

By reading the two methods, and by checking coverage:
`spec/controllers/project_workflows_graph_spec.rb` covers `role_id: ['1e5']`
(invalid alone → 404) and `role_id: {'x' => 'y'}` (a Hash), but has no example
for the mixed case. Credit where it is due: this was found by the ChatGPT review
Jan commissioned in parallel and confirmed here.

**Suggested direction**

Resolve all requested ids and answer 404 unless every one of them resolved, which
is what the comment already promises. The same question applies to
`ProjectWorkflowScopesController#resolve_ids`, which already takes that stricter
shape — the two should agree.

**Resolution:** fixed. `#unresolved_role_ids` answers with the ids the
request named that no offered role matched, de-duplicated the way the copy
screen's `#unresolved_target_ids` already de-duplicates, and
`#find_tracker_and_roles` answers 404 when it is not empty. The empty-result
branch stays, because a project that offers no role at all is not a missing page.

Three examples, two of them red on the old code: one valid id beside one that
names nothing, and one valid id beside a role the project does not offer. The
third pins the other side of the rule -- the same id twice is one selection, not
a missing record -- and passes either way by design.

The four methods moved into `RedmineProjectWorkflows::GraphSelection`, because
the addition took `Metrics/ClassLength` to 204/200 and that controller's own
comment says what to do about it: "crossing it is a signal to extract, not a cop
to placate." Every method there is private, for the reason `MatrixParams` and
`MatrixReporting` give.

---

### F06 — Three core methods the plugin shadows are not in the drift digest, including the two INV-1 rests on

- **Status:** open
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** portability
- **Where:** `lib/redmine_project_workflows/services/core_method_digest.rb:47-56`
  (`TARGETS`), `spec/upstream/core_method_digests.yml`
- **Invariant touched:** none

**What is wrong**

`CoreMethodDigest::TARGETS` lists six classes whose *instance* methods are
shadowed. The plugin also prepends three singleton classes, and those shadows are
invisible to it:

```
WorkflowRule.copy_one            replaced by WorkflowRulePatch
WorkflowTransition.replace_transitions   replaced by WorkflowTransitionPatch
WorkflowPermission.replace_permissions   replaced by WorkflowPermissionPatch
```

The last two are the methods INV-1's whole routing rests on. A fourth dependency
is not a shadow at all and is therefore also absent: `Issue#roles_for_workflow`,
a **private** core method three services call through `send`, and the one
`init.rb` names as the hard reason the Redmine floor is 5.1.

**Why it matters**

The drift gate exists because a semantic change under a copied body is otherwise
silent. It watches nineteen of the twenty-two shadows and none of the private
dependency. A change to core's `replace_transitions` — for instance to what it
accepts, or to whether it validates — would pass the gate green.

**How I verified it**

On the running host, outside the spec suite:

```
available?=true
digests computed at runtime: 19 in 34.5 ms
--- singleton patches NOT covered by TARGETS ---
  WorkflowRule: [:copy_one_for_project, …, :copy_one, …]
  WorkflowTransition: [:replace_transitions]
  WorkflowPermission: [:replace_permissions]
```

The 34.5 ms is worth recording separately: it means the digest can be computed
at **runtime**, not only in a spec, which is what ADR-002 builds on.

**Suggested direction**

Extend `TARGETS` to singleton classes, so the discovery stays discovery rather
than becoming a hand-kept list. Add `Issue#roles_for_workflow` as a declared
dependency of its own — it is called, not shadowed, so it needs a second kind of
entry.

**Resolution:**

---

### F07 — A generic matrix write takes no lock, so two administrators can still leave duplicate rows

- **Status:** fixed 2026-08-29 (WP13 step 1) — see Resolution
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** concurrency
- **Where:** `lib/redmine_project_workflows/services/matrix_scope.rb:36-38`
  (`writable_pairs` returns every pair unlocked when `project_id` is nil),
  `spec/services/workflow_concurrency_spec.rb:96`
- **Invariant touched:** none

**What is wrong**

Project writes take `SELECT … FOR UPDATE` on the scope rows they are about to act
on, which is what makes "does this project own its workflow here?" and "write its
rules" one decision. A generic write has no scope row, takes nothing, and runs
delete-then-insert against rows another transaction may be deleting and
reinserting at the same moment. The asymmetry is deliberate and pinned: the
concurrency spec asserts "the lock … is not taken for a generic write."

**Why it matters**

The README already documents the outcome — duplicate rows, and a matrix cell that
renders as a mixed dropdown instead of a checkbox — and ships a repair rake task
for it.

The important calibration, and the reason this is minor rather than major: **core
has the identical race and the plugin inherited it.** Core's
`WorkflowTransition.replace_transitions` reads `records = …to_a` outside any lock
and core's `replace_permissions` does destroy-then-create per cell. Core is aware
of it, too — `replace_transitions` carries an opportunistic
`if w.size > 1 then w[1..-1].each(&:destroy)` that repairs duplicates on every
save. So this is not a regression the plugin introduced; it is a core defect the
plugin is now unusually well placed to fix, because it already owns both write
paths and already has the locking discipline for one of them.

**How I verified it**

By reading core's two writers in a 5.1-stable checkout and the plugin's
`writable_pairs`, and by reading the spec that pins the current behaviour. Not
reproduced with two connections: the local host was SQLite, which serialises
writers.

**Suggested direction**

One write-coordination service with a deterministic key —
`(rule_type, project-or-generic, tracker, role)` — taken in a fixed order by all
four write paths, so generic and project writes have one concurrency policy
instead of two. A plugin-owned lock table rather than advisory locks, which have
no portable equivalent across PostgreSQL, MySQL and MariaDB. The existing spec
that asserts the asymmetry is the one that has to be inverted, and saying so is
part of the fix.

**Resolution:** Done on 2026-08-29, as the suggested direction with one
deliberate difference.

`Services::WriteCoordinator` is the single entry point, and a caller names one
key: `(rule_type, project-or-generic, tracker, role)`. What that key resolves to
differs by population, and that is the difference from the suggestion. A
project's **scope row** is its coordination row — it already exists exactly when
the combination is writable, which is what makes "may I write this?" and "nobody
else may while I do" one statement, and it is what 0.1.2 built. The generic
population gets a row on a plugin-owned table, `project_workflow_write_locks`
(migration 007), which carries nothing but the key. Giving the generic workflow a
*scope* row instead would have been a fourth state in a model whose whole purpose
is that there are three (INV-3). A plugin-owned table rather than advisory locks,
for the portability reason the finding gives.

The order is fixed: ascending primary key within a table, and the generic rows
after any project scope rows — which the callers already do, because
`WorkflowSelection#selected_project_ids` appends the generic `nil` last.

The write paths that take one: both rule writers (which is also how Redmine's own
workflow save reaches it, INV-1), the three scope actions, and **both** copy
screens. That last one was a gap in the first draft worth recording: the lock was
taken in the plugin's copy controller, and Redmine's own copy screen writes
generic rules through core's `WorkflowRule.copy` → the plugin's `.copy_one` →
`.copy_one_for_project` without going near it. It is taken in the model beside
the write now, so both screens reach it. The one write that takes nothing is
`WorkflowRule.copy_one_with_projects`, which duplicates a role or tracker that
has just been created and that no other request can name.

The spec that pinned the asymmetry — *"is not taken for a generic write"* — is
inverted and says so in place. Red on the old code, observed rather than assumed:
with `lock_generic` returning early, two connections saving the same generic cell
leave **two** rows (`spec/services/workflow_concurrency_spec.rb`, run on
PostgreSQL 16 and MariaDB 10.11). The pause in that example is between the delete
and the insert, and has to be: pausing before the delete proves nothing, because
READ COMMITTED lets the second delete see the first connection's committed row
and remove it.

---

### F08 — An administration matrix save wraps the whole selection in one transaction, and the row count is unbounded

- **Status:** open
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** performance
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_patch.rb:70-80`
  and `:143-153`
- **Invariant touched:** none

**What is wrong**

The single transaction is deliberate and right — a failure half way through would
otherwise leave part of the selection rewritten. What is not bounded is what goes
inside it. A selection of "all projects" × "all trackers" × "all roles" rewrites
every cell for every combination while holding scope-row locks for the duration.

**Why it matters**

Measured on the running host with a full transitions matrix (3 trackers, 3 roles,
6 statuses, 36 cells) across 5 projects:

```
one save over 5 projects: 63 ms, 48 SQL statements
rows now: 1620
rows per project per save: 324
```

The statement count is well-behaved — about 9.6 per project, constant, no
per-row round trip. The row count is not. A realistic large installation (500
projects, 5 trackers, 8 roles, 20 statuses) extrapolates to roughly **8 million
rows deleted and reinserted in one transaction**, during which every other
administrator and every project manager saving their own matrix blocks. A
front-end proxy timing out rolls the whole thing back with no partial progress.

Earlier review work measured the *read* paths at scale (123 projects, 16,205
rules, every screen under 260 ms). The write path had not been measured.

**How I verified it**

The numbers above, from a probe script on the 5.1 host that built the projects,
enabled scopes, submitted a full matrix and counted `sql.active_record`
notifications.

**Suggested direction**

Keep the transaction. Bound the selection: project the row count before
executing — `project_workflow_selection_size` already computes the multiplier —
and put a confirmation in front of a save that crosses the threshold the plugin
setting already carries, or refuse above a configured ceiling. Not a background
job: Redmine 5.1's default ActiveJob backend is the async adapter, which is not
something a workflow write should depend on.

**Resolution:**

---

### F09 — Every administration workflow page renders one option per project, archived ones included

- **Status:** open
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** performance
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_project_selection.rb:38`
  (`@projects = Project.sorted`),
  `app/views/redmine_project_workflows/_project_selector.html.erb:6`,
  `app/controllers/project_workflow_inventories_controller.rb:41`
- **Invariant touched:** none

**What is wrong**

The project selector on `workflows/edit`, `workflows/permissions`,
`workflows/index` and `workflows/copy` is built from every project on the
installation, with no pagination and no autocomplete; the inventory additionally
materialises the whole list with `.to_a`. `Project.sorted` carries no status
predicate, so archived projects are offered too, where core's own project pickers
scope to visible or active projects.

**Why it matters**

Page weight rather than query count — the plugin already avoids the query
explosion by carrying `all` verbatim instead of expanding it. On a
three-thousand-project installation four administration pages each carry a
several-hundred-kilobyte `<select>`. A workflow written for an archived project
is inert, so offering one is noise.

**How I verified it**

Read; the code is unambiguous. Not measured at scale.

**Suggested direction**

Reuse Redmine's own control for large project lists and exclude
`Project::STATUS_ARCHIVED` from what is offered. The parameter is still
intersected server-side either way, so nothing about INV-7 changes.

**Resolution:**

---

### F10 — `deface` is unconstrained, which protects an existing installation and not a new one

- **Status:** open
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** dependency
- **Where:** `Gemfile:1-22`, `init.rb:57-60`
- **Invariant touched:** none

**What is wrong**

The Gemfile's reasoning is sound as far as it goes: the host owns
`Gemfile.lock`, so a constraint in a plugin fragment cannot protect an existing
installation, and it *can* import a neighbouring plugin's resolver conflict into
a host that has none. What it does not cover is a **new** installation, or a host
running `bundle update`, where Bundler resolves whatever `deface` release exists
that day. `init.rb` turns a load failure into a `LoadError` that stops Redmine
booting.

**Why it matters**

A future incompatible `deface` can stop the host booting, or load while some
overrides silently stop matching. The control that exists instead —
`spec/integration/deface_overrides_spec.rb` on nine cells — catches the second
case in CI and nothing catches either case on an administrator's machine.

**How I verified it**

Read. Not reproduced; it is a claim about future releases.

**Suggested direction**

A lower bound at the known-good version and an upper bound at the next major.
That is strictly narrower than the unconstrained declaration and cannot import
the conflict the comment fears, because a neighbour pinning within the same major
still resolves. ADR-003 reduces the exposure from a different direction, by
taking the override count from fifteen to two.

**Resolution:**

---

### F11 — `ScopeCopier` does not apply the rule `ProjectWorkflowCopier` states

- **Status:** open
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** code-quality
- **Where:** `lib/redmine_project_workflows/services/scope_copier.rb:60-83`
  against `lib/redmine_project_workflows/services/project_workflow_copier.rb:70-73`
- **Invariant touched:** none

**What is wrong**

`ProjectWorkflowCopier` deliberately narrows to the target project's own trackers
and says why: "a scope for a tracker the project does not have is a decision about
nothing". `ScopeCopier`, which runs when an administrator duplicates a tracker or
a role, copies a scope for every project that had one on the source pair,
including projects that will never enable the new tracker.

**Why it matters**

Inert rows rather than wrong behaviour — the settings tab hides trackers the
project has not enabled. But if that tracker is later enabled on such a project,
the project arrives with an own workflow it never decided on. Two copiers, two
answers to one question, and only one of them written down.

**How I verified it**

Read.

**Suggested direction**

Either narrow `ScopeCopier` the same way, or record the asymmetry in
`docs/DECISIONS.md` as deliberate — "duplicating a tracker duplicates every
project's decision about it" is defensible. What should not survive is a
difference that reads as an oversight.

**Resolution:**

---
