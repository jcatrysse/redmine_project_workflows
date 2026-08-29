# Review run — 2026-08-29 — Claude Code (Opus), revalidation + external review folded in

- **Reviewer:** Claude Code (Opus 5), in a Claude Code on the web container
- **Commit reviewed:** `9f42909`
- **Ran the test suite:** yes — a Redmine 5.1-stable host rebuilt from scratch here.
  **1251 examples, 4 failures, 18 pending**; the four are SQLite artefacts and are
  F06 below. RuboCop through `.github/lint/Gemfile`: **152 files, no offences**.
  `node dev/check-bulk-js.mjs`: pass. CI run **187** on this exact head:
  **11/11 jobs green**, read from the Actions API — the 3 x 3 matrix with
  **19 steps per database cell**, including the upgrade rehearsal from the
  previous release, the rehearsal over populated data and the uninstall/restore
  rehearsal.
- **Scope covered:** two jobs in one run. First, revalidating every finding of
  `2026-08-28-claude-audit.md` **behaviourally** rather than by reading its
  `Resolution:` lines. Second, verifying the five findings of a second ChatGPT
  review Jan commissioned, and adding what neither review had. Probes written and
  run here: 21 routes x 3 actors; permission separation and cross-project
  substitution; INV-1 through core's now-unpatched save; INV-3 on the rewritten
  administration matrix; the four compatibility states; the bulk ceiling
  end-to-end; an interrupted restore and its retry.
- **Scope NOT covered:** only Redmine 5.1 was built locally, and on SQLite — the
  `pg` gem cannot be built in this container, so every cross-database and
  cross-version claim rests on CI run 187 rather than on a local cell. No browser.
  No neighbouring plugins installed this run. The six non-authoritative locales
  were checked for parity, which is not a translation review.

## Summary

The plugin got materially better, and I checked rather than assumed. Every one of
my eleven findings from the day before is genuinely fixed or deliberately
settled, and several of the fixes are better than what I specified — the
compatibility object grew a fourth state (`:unmeasured`) so the plugin never says
"no drift detected" when it detected nothing; the write-lock table is keyed per
(rule type, tracker, role) rather than per project, so it is tens of rows rather
than tens of thousands; and the diagnostics page verifies each Deface anchor
against the running Redmine, which closes the one gap ADR-002 said the digest
check does not cover. The Deface surface went from fifteen overrides in twelve
files to five in three, the workflow controller patch from 468 lines to 46 lines
of code, and prepends on core *helpers* from one to none. Authorization is clean:
21 routes x 3 actors, every one correct, with view and manage properly separated
and no project route reaching another project.

What is not right is the recovery tooling WP16 added, and that is where the
external review earned its keep. **A restore that is interrupted leaves every
prepared-but-unwritten combination as an own *empty* workflow — no status change
permitted at all — and the documented retry then skips exactly those.** I
reproduced it. A backup is assembled from two unlocked queries with no
transaction, so it can hold a state that never existed. And the administration
matrix resolves trackers and roles with `where(id: ids).to_a` and writes whatever
survives: `tracker_id=1e5` writes to tracker 1 and reports success, which is the
very cast this repository warns about in its own comments, on the one write path
that never got the treatment the graph, the copy screen and the scope routes all
got.

The distinction that decides the verdict: the **runtime** is sound and measured;
the **recovery tooling** is not. That is a different category of risk — a rake
task an administrator starts deliberately, not a path every issue save takes —
but it is the tooling the uninstall procedure rests on, so it blocks a release.

**Counts:** blocker 1 · major 2 · minor 2 · nit 3 · question 0

---

### F01 — An interrupted restore leaves workflows owned but empty, and the documented retry skips them

- **Status:** fixed
- **Severity:** blocker
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `lib/redmine_project_workflows/services/workflow_restore.rb:82-94`
  (`call`), `:119-141` (`prepare`); `README.md`, the "Running the restore twice
  is safe" paragraph
- **Invariant touched:** INV-3 — the three states stay distinguishable, and this
  moves combinations into the third one by accident
- **Credit:** raised as RESTORE-001 by the ChatGPT review of 2026-08-29;
  reproduced here.

**What is wrong**

`WorkflowRestore.call` runs `prepare` over **every** restorable combination
first — creating each missing scope and clearing each overwritten one — and only
then loops `write_one` per combination. There is no transaction around the whole
thing and none around each combination. So the window between "all scopes exist"
and "this combination's rules are written" is the entire length of the restore.

`select_restorable` skips a combination when `referents.scoped?(key)` and
`overwrite` is false. After `prepare`, that is true of every combination the
restore was going to write.

**Why it matters**

A scope with no rules is an own *empty* workflow, which for transitions means no
issue in that project can change status for that role — the state the README
itself singles out as the most consequential the plugin can be in. An interrupted
restore therefore does not fail safe: it fails into deny-all, silently, for every
combination it had not reached. And the retry the README recommends reports that
everything was left alone and changes nothing.

The README's sentence is literally true and operationally misleading: *"Running
the restore twice is safe: the second run reports that everything was left alone
and changes nothing."* True after a success; a trap after a failure.

**How I verified it**

Three projects each given their own workflow and one rule, backed up, wiped as a
downgrade would, then restored with `write_one` raising after the first
combination:

```
backup holds: 3 scopes, 3 rules
interrupted: simulated: connection lost
after the crash:
  project 1: scope=yes rules=1
  project 2: scope=yes rules=0   <-- OWN EMPTY = no transition permitted
  project 3: scope=yes rules=0   <-- OWN EMPTY = no transition permitted

default retry: scopes=0 rules=0 skipped_existing=3
  project 2: rules=0   <-- STILL EMPTY after retry
  project 3: rules=0   <-- STILL EMPTY after retry
```

Only `OVERWRITE=1` recovers it, and nothing tells the operator that.

**Suggested direction**

Per-combination atomicity: transaction, lock, scope, rules, audit, commit — one
combination at a time. A failed combination rolls back to what it was; a
completed one is genuinely safe to skip, which makes the default retry correct
rather than dangerous. The alternative, one transaction around the whole restore,
gives the same guarantee and holds a lock for the length of a large restore; the
per-combination shape avoids that and is what the writers already do everywhere
else.

The report needs to tell four things apart where it now says two: restored,
skipped because identical, skipped because it exists and differs, failed. And the
README sentence has to say what holds after an *interrupted* run.

**Resolution:** WP17. `WorkflowRestore` now restores **one combination in one
transaction** — lock, scope, rules, audit, commit — so a combination is either
wholly restored or wholly rolled back to inheriting; neither state needs
`OVERWRITE=1` on a retry, and an operator does not have to know which happened.
A failure no longer stops the restore: the other combinations are finished and
the failed ones are named, individually, in the report. The rake task exits
non-zero when any failed, because a restore is what runs unattended.
`spec/services/workflow_restore_recovery_spec.rb` is the reproduction above,
inverted: twelve examples, the seven about interruption all red on the previous
code (verified by restoring it), including the interrupted-then-retried round
trip and the rollback of an interrupted `OVERWRITE=1` run.

The report's other conflation is gone too: "left alone" now says how many of
those combinations **differ** from the backup, which is the number that decides
whether `OVERWRITE=1` would change anything. Compared as sets of what each rule
permits (`RestoreComparison`), in one query for the whole run, so the duplicate
rows a pre-0.1.6 database can carry are not reported as a change that a restore
would not make. The README sentence is replaced by one that says what holds
after an interrupted run.


---

### F02 — A backup is assembled from two unlocked queries, so it can hold a state that never existed

- **Status:** fixed
- **Severity:** major
- **Confidence:** confirmed
- **Category:** concurrency
- **Where:** `lib/redmine_project_workflows/services/workflow_backup.rb`,
  `document`; `lib/redmine_project_workflows/tasks.rb`, `uninstall`
- **Invariant touched:** none directly; it undermines what INV-3 records
- **Credit:** raised as BACKUP-001 by the ChatGPT review of 2026-08-29.

**What is wrong**

```ruby
def self.document
  scopes = scope_rows
  rules  = rule_rows
```

Two independent queries, no transaction, no coordination lock — and `grep` for
`transaction|lock|WriteCoordinator` in that file returns nothing. A concurrent
enable, clear, inherit or matrix save between them produces a document in which
the decisions and the rules describe two different instants.

The uninstall task widens the window further: build the document, print counts,
ask for confirmation, write the file, reverse the migrations. A project manager
can change a workflow anywhere in there, and the migration reversal then deletes
the live state.

**Why it matters**

The two populations are not independent. A scope with no rules means *own empty*;
no scope means *inherits*. A torn read can produce a scope whose rules are gone,
or rules whose scope is gone — and the second is invisible to the resolver
(INV-3), so restoring the file produces a different workflow from the one that
was backed up. For destructive uninstall that is permanent.

**How I verified it**

By reading, not by racing: the absence of a transaction is not a thing that needs
reproducing, and a two-connection demonstration belongs in the regression test
rather than in the finding.

**Suggested direction**

Two separate problems, two fixes. The torn read wants the two queries inside one
transaction with an isolation level that gives a consistent snapshot on each
supported adapter — PostgreSQL needs `repeatable_read` asked for explicitly,
MySQL and MariaDB have it by default. The export-to-destruction gap wants
something cheaper than locking every workflow for the length of an operator
prompt: a single monotonic revision that the write coordinator bumps, carried in
the backup, and re-checked immediately before the migrations run. If it moved,
refuse and say so.

**Resolution:** WP17. Both reads are taken in one snapshot —
`WorkflowBackup.snapshot`, at `repeatable_read` where the adapter gives it, and
joining a transaction that is already open rather than nesting inside one. The
fallback is the refusal caught, not a capability asked about in advance:
SQLite answers `supports_transaction_isolation?` with **true** and then refuses
every level but `read_uncommitted`. It is a retry rather than a resume because
Rails begins a transaction lazily, so on Rails 6.1 the refusal arrives from
inside the block — which `dev/check-uninstall.sh` caught, and which two examples
now pin from both sides. The uninstall gained a second guard for the *other*
window this finding implies: the export is taken, a human is asked to type
CONFIRM=yes, and a colleague can save a workflow while that question is on the
screen. `Tasks.refuse_if_changed!` re-reads and compares before any migration
runs, and refuses rather than destroying a workflow the file does not hold.


---

### F03 — The administration matrix writes whatever resolves, so `tracker_id=1e5` writes to tracker 1 and reports success

- **Status:** fixed
- **Severity:** major
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `app/controllers/project_workflow_rules_controller.rb`,
  `find_selection` and its two callers `find_roles` / `find_trackers`
- **Invariant touched:** none — it is administrator-only, and does not widen
  access
- **Credit:** raised as INPUT-001 by the ChatGPT review of 2026-08-29;
  reproduced and sharpened here.

**What is wrong**

```ruby
def find_selection(all, klass, ids)
  ...
  klass.where(id: ids).to_a
```

Whatever resolves is the selection. A value that names nothing is dropped; a
value of the wrong shape is *cast*. This is core's own `find_roles` /
`find_trackers`, carried across unchanged when WP12 moved the screen into the
plugin — at which point it stopped being core's problem and became this one.

Every other selection on the plugin now refuses a value it cannot resolve: the
graph does (`2026-08-28-claude-audit` F05), the copy screen does, the scope
routes check the shape as well as the record. The matrix is the only one that
does not, and it is the one that writes.

**Why it matters**

Administrator-only, so this is not an access defect — it is a silent wrong write
to authorization configuration, reported as a success. A stale browser form
naming a tracker deleted since it was rendered writes the rest and says
*Successful update*. And the shape case is worse than "dropped": Rails casts
`'1e5'` to `1`.

**How I verified it**

On the running host, as an administrator:

```
valid + nonexistent tracker -> ["Successful update."]
  trackers actually written: [1]   (asked for [1, 999999])
'1e5' as tracker_id -> rows written for tracker: [1]   (Tracker 1 is "Bug")
graph with valid + nonexistent role -> 404   (fixed in WP10)
```

The last line is the contrast: the same shape, refused on the screen that was
fixed and accepted on the screen that writes.

**Suggested direction**

One exact-selection resolver, used by the matrices, the copy screen, the graph
and the scope routes. Normalise to unique strings, keep the `all` keyword
explicit, require `/\A\d+\z/`, resolve, and fail before any write if anything
went unresolved. There are four resolvers with four strictnesses today and the
least strict is the one that writes; the external review is right that
consolidating them is the fix rather than patching this one.

**Resolution:** fixed in WP18. `Services::ExactSelection` is the one resolver:
normalise to unique non-blank strings, split the keywords this control accepts,
require `/\A\d+\z/` before an id goes anywhere near a query, resolve against
the list the screen offers (or, for the one selector that may legitimately name
a record it does not offer -- an archived project reached from the inventory --
against a relation), and report everything the request named that no record
answered. The four call sites are on it: the administration matrices' trackers
and roles, the project selector, the copy screen's two target selectors, and the
graph's roles. A matrix request naming anything unresolvable answers 404 before
any write, which matters because a matrix save deletes before it inserts.
`spec/services/exact_selection_spec.rb` covers the shapes; twelve of them are
driven end to end through the writing screen, and the eight that were the defect
were verified red against the previous code. Two behaviours tightened on the
way, both deliberate: the copy screen's target roles now resolve against the
list the form offers rather than against every Role, and a matrix selection
comes back in candidate order rather than the order the browser submitted.

---

### F04 — The backup file is written non-atomically, at whatever the umask allows

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** security
- **Where:** `lib/redmine_project_workflows/services/workflow_backup.rb`, `write`
- **Credit:** raised as BACKUP-002 by the ChatGPT review of 2026-08-29.

**What is wrong**

`File.write(path, ...)` straight to the final path. No temporary file, no
`fsync`, no explicit mode. The README tells the operator the file holds project,
tracker, role and status names and should not be world-readable; the code does
nothing to make that true.

**Why it matters**

Measured on this host: **mode 0644** under the ordinary umask 0022. And
`FORCE=1` destroys a previous backup before the replacement is durable, so an
interruption can leave neither. The uninstall task reads the file back before
reversing the migrations, which catches plain truncation — that is what keeps
this minor rather than major.

**How I verified it**

```
mode: 644
umask: 22
```

**Suggested direction**

Temporary file in the target directory at mode 0600, write, flush, `fsync`,
validate by reading it, then rename into place. Keep the previous file until the
new one is durable.

**Resolution:** WP19. `WorkflowBackup.write_atomically`: a temporary file
beside the target -- a rename is only atomic within one filesystem, and a backup
path is exactly the kind of path that is a mount of its own -- chmodded 0600,
written, flushed, `fsync`ed, **read back before the rename** so that a file that
does not parse can never become the backup, then renamed into place, with the
directory entry synced after. The previous file survives until the new one is
durable. Two examples: the mode, and that a failed write leaves the previous
file and no debris behind.


---

### F05 — A drifted or unmeasured host warns in the log and on one page, and nowhere the operator is actually writing

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** operability
- **Where:** `lib/redmine_project_workflows/compatibility.rb`, `announce!` and the
  message builder; the plugin's own administration and project screens
- **Credit:** raised as COMPAT-002 by the ChatGPT review of 2026-08-29, which
  asked for writes to be refused; **answered A by Jan on 2026-08-29** — warn and
  continue, as ADR-002 already decided.

**What is wrong**

The four states are right and the diagnostics page is good, but a `:drifted` or
`:unmeasured` host announces itself in the application log and on a page nobody
has to visit. The screens where somebody is about to change workflow rules say
nothing.

The external review proposed refusing writes until an administrator
acknowledges the version and digest set. That is a real third option and it
sidesteps ADR-002's objection to blocking — Redmine still boots, reads still
work, the diagnostics page stays open. **Jan chose A**: warn and continue. This
finding is therefore about the warning being where it is needed, not about the
policy.

**Why it matters**

Workflow logic is authorization logic. A Redmine minor that changed
`WorkflowPermission.replace_permissions` under the plugin is exactly the case the
compatibility object exists to catch, and catching it into a log line the
administrator never reads is most of the value thrown away.

**How I verified it**

The four states all resolve correctly here (`:verified`, `:unverified`,
`:drifted`, `:unmeasured`), and `announce!` is a log line; the diagnostics page
is the only surface that shows the state.

**Suggested direction**

A persistent banner on the plugin's own administration screens and on the project
Workflow screens whenever the state is not `:verified`, naming the state and
linking to the diagnostics page. No refusal — that is Jan's answer, and reversing
it is a one-line policy change if the question ever comes back.

**Resolution:** WP19. `project_workflow_compatibility_banner`, on the seven
screens where a workflow rule is about to change: both administration matrices,
the summary, the copy screen, the two project matrices and the project's
Workflow settings tab. It names the state in one sentence and, for an
administrator, links to the diagnostics page -- not for anybody else, because
that page requires an administrator and a link to a 403 tells a project manager
less than the sentence already did. Nothing at all on a verified host, which is
the common case: a banner that is always there is furniture. Still a warning and
never a refusal, which is ADR-002 and Jan's answer A of 2026-08-29; reversing it
is a change in this one method. `spec/views/compatibility_banner_spec.rb` drives
every one of the seven screens in all four states, so a screen added later
without the banner fails there rather than being noticed on a drifted host.


---

### F06 — Four specs assert a statement SQLite cannot parse, with no adapter guard

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** test-quality
- **Where:** `spec/services/scope_bulk_writer_batching_spec.rb`

**What is wrong**

The batching examples build a delete of exactly `DELETE_BATCH_SIZE` (500) OR'd
triples. On SQLite that is `SQLite3::SQLException: parser stack overflow`, and
the spec's own header says so — *"SQLite fails well under a hundred"* — without
guarding for it. The repository already has the idiom: nine concurrency examples
call `skip('the adapter has no row locking to assert')`.

**Why it matters**

Not a product defect: SQLite is not one of the nine supported cells, and
`spec/spec_helper.rb` says as much. The cost is that a developer on a SQLite host
sees four red examples and has to work out that nothing is wrong, and that "the
suite is green" is a claim only about the nine cells.

**How I verified it**

Local suite on this host: **1251 examples, 4 failures, 18 pending**, all four
failures in that file with that exception. CI run 187: green on all nine cells.

**Suggested direction**

The same skip the lock examples use, on the same question — whether this adapter
can plan a statement of that shape.

**Resolution:** WP17, taken along with F02 because the guard it needed is the
predicate F02's own two-connection example needed. `spec_helper.rb` gained
`supported_adapter?` — one of the nine cells, as against the SQLite a container
falls back to — and the four batching examples skip on anything else, which is
the idiom the nine concurrency examples already use.


---

### F07 — Two entries in Administration where ADR-003 costed one

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** ux
- **Where:** the `admin_menu` registrations

**What is wrong**

*Project workflows* and *Project workflow diagnostics* are both top-level entries
in Redmine's administration menu. ADR-003 accepted one extra entry as the price of
owning the screens; this is a second, for a page an administrator visits when
something is wrong.

**Suggested direction**

A link from the *Project workflows* screen rather than a menu entry of its own.
The page keeps its route and its `require_admin`.

**Resolution:** WP19. The diagnostics entry is out of Redmine's
administration menu and into the action bar of the plugin's own administration
area, which is rendered on all four of its screens -- where somebody who has just
read the banner is standing. The page keeps its route and its `require_admin`.
The spec that asserted the menu entry now asserts the opposite, that the plugin
contributes exactly one line to that menu, which is what ADR-003 costed.


---

### F08 — `docs/release-criteria.md` R1 cites a commit two runs behind the head

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** docs
- **Where:** `docs/release-criteria.md`, the "Where this stands" table

**What is wrong**

R1 reads *"met on the last commit CI has answered for (run 180, `8a2e240`)"*.
Run **187** on the head `9f42909` is green on all eleven jobs.

The criterion is self-aware — it says a green run is only ever true of a commit
and to re-check it on the release commit — so this is staleness rather than a
wrong claim.

**Resolution:** WP19. R1 now names run 190 on `0d36552`, and says in the
line itself that it goes stale on the next push -- which is why it names the run
as well as the commit, and why the release procedure re-checks it on the release
commit.


---

## Checked and found sound

Recorded so the next reviewer does not re-derive it.

- **All eleven findings of `2026-08-28-claude-audit.md`**, revalidated
  behaviourally rather than from their `Resolution:` lines. The generic write now
  takes a coordination row (9 lock statements, 1 row); the ceiling refuses an
  oversized enable end-to-end and writes nothing; the drift gate covers 26
  methods including the three singleton shadows and `Issue#roles_for_workflow`;
  archived projects are out of the selectors; `deface` is `~> 1.9`.
- **Authorization**, on 21 routes x 3 actors: anonymous → login redirect,
  logged-in without the permission → 403, administrator → works. View and manage
  are properly separated (view-only gets 403 on PATCH and on enable), and no
  project route reaches another project.
- **INV-1 through core's now-unpatched save.** `WorkflowsController#update` is no
  longer patched, but `replace_transitions` and `replace_permissions` still route
  through the plugin's writers: a generic save wrote one generic row and left the
  project's rule alone. A stale bookmark carrying `project_id` on core's screen
  renders generic only.
- **INV-3 on the rewritten administration matrix.** A selection holding one
  project that decided and one that inherits writes the first, leaves the second,
  creates no scope, and says so in two flash messages — the second of which now
  reads better than it did: *"…was not changed. Give it its own workflow first."*
- **Locale parity**: 175 keys across all eight files, nothing missing, nothing
  extra, nothing left in English.
