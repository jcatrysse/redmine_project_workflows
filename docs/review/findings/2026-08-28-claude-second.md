# Review run — 2026-08-28 (second) — Claude Code (Opus)

- **Reviewer:** Claude Code (Opus 5)
- **Commit reviewed:** `efaf67c`
- **Ran the test suite:** yes — Redmine 7.0-stable + PostgreSQL 16, rebuilt from
  scratch in this container. **834 examples, 0 failures** (was 808; twenty-six
  added). RuboCop through `.github/lint/Gemfile`: **115 files, no offences**, with
  `.rubocop.yml` and `.rubocop_todo.yml` unchanged since `0853e06`.
  `node dev/check-bulk-js.mjs`: 34 checks pass. CI run **131** on this exact head:
  **success**, read from the Actions API.
- **Scope covered:** first, whether F01..F05 of `2026-08-28-claude.md` are really
  fixed — each re-tested against the shape it was found in, on a live Redmine.
  Then a deliberately different pass, aimed at the question "can this go on a real
  system": **data lifecycle** (project copy, project / role / tracker / status
  deletion, role and tracker duplication), **project state** (closed, archived),
  **anonymous access on a public project**, **concurrency** (22 simultaneous
  writers), **scale** (123 projects, 542 scopes, 16,205 project rules — screen
  timings and query counts), **reversibility** (`VERSION=0` on the *populated*
  database, not an empty one), **accessibility** of the new drawing, **locale
  parity and translation quality**, and a fresh sweep of INV-1..9 and the
  forbidden-constructs table.
- **Scope NOT covered:** no MySQL or MariaDB host was built this session, so
  cross-database claims rest on CI run 131 rather than a local cell; no LDAP, no
  REST API, no email; the six non-authoritative locales were read for plausibility
  by a non-native reader, which is not a review; no upgrade rehearsal from an
  *older version of this plugin* to the current one, only from stock Redmine.

## Summary

All five findings of the first run are genuinely fixed, and I re-tested each one
against the exact shape that produced it rather than against the resolution text.
On a Redmine installed with nothing but `redmine:load_default_data` — the
configuration F01 was about — the diagram now draws Redmine's own fallback to the
tracker's default status as a dotted arrow, no status lands in the unreachable
band, and the diagnostics read "every status can be reached and has a way out".
The dense case F03 named is detected and folded away behind *Show the diagram
anyway*, with a sentence that says why. The band has its own layering. The panel
no longer contradicts the status list. The two action links have a separator.

The fixing session also rejected one of my two suggested directions for F03, and
it was right to: ranking by shortest path breaks the guarantee that a forward
edge spans at least one layer, which the routing and the straightening both rely
on. My finding claimed the change "belongs in `WorkflowGraphRanking` alone"; that
was wrong, and the resolution says so with the reasoning.

The second pass is where I expected to find trouble and mostly did not. Deleting a
project, a role or a tracker takes its scopes and its rules with it through real
foreign keys — no orphans, measured. A closed project reads and refuses every
write with 403, and the UI does not draw buttons it cannot honour. An archived one
refuses everything. Duplicating a role or a tracker carries all 10,805 project
rules *and* the 181 scopes that make them visible, and the copy resolves to the
same graph as the source. Twenty-two concurrent writers on one combination
produced no duplicate rows and left the generic workflow untouched. At 123
projects and 16,205 project rules every screen answers in under 260 ms and the
diagram costs seven queries flat. `VERSION=0` on that populated database removed
the column, the table, the foreign key and its own `schema_migrations` rows, left
the generic workflow at exactly 144 rules and every project, issue and user
intact, and migrating back up restored the lot.

**My answer to "can we test this on a real system" is yes**, with two operational
things to know rather than fix: take a database backup before installing, because
`VERSION=0` deletes every project's own workflow instantly and the README already
says there is no way back; and know that **copying a project does not copy its
workflow** (F01 below), which is the one behaviour most likely to surprise
somebody in the first week.

**Counts:** blocker 0 · major 0 · minor 1 · nit 2 · question 0

---

### F01 — Copying a project does not carry its own workflow, and nothing anywhere says so

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `lib/redmine_project_workflows/patches/project_patch.rb` (the patch
  exists and touches only `rolled_up_statuses`), against core's
  `app/models/project.rb:952`
- **Invariant touched:** none

**What is wrong**

Redmine's *Copy project* copies what `Project#copy` lists:
`members wiki versions issue_categories issues queries boards documents`. The
plugin adds nothing to that list, hooks neither `model_project_copy_before_save`
nor anything else, and has no `Project#copy` patch. So a project that runs its own
workflow, copied, arrives running the **generic** one — with no message, no
warning, and nothing in the README, `docs/design.md`, `docs/DECISIONS.md` or any
ADR that says this is what happens.

The direction of the surprise is the wrong way round. A project is usually given
its own workflow to make it *stricter* than the generic one; the copy therefore
comes out **more permissive** than the original, and its members are the ones the
copy brought along.

**Why it matters**

A concrete path, and it is an ordinary one: a team sets up a project with a
deliberately narrow workflow — say four permitted transitions where the generic
workflow permits thirty — and copies it to start the next engagement from the same
shape. Members, trackers, categories and issues all come across. The workflow does
not. Nobody is told. The new project silently permits every transition the generic
workflow does, and the first sign of it is somebody closing an issue that should
not have been closeable.

**How I verified it**

On a live Redmine 7.0 host, with `Project#copy` — core's own method, the one the
*Copy* button calls:

```
uitgangspunt   pilot: scopes=2 rules=5
copy geslaagd: true
kopie:         scopes=0 rules=0
issues meegekomen: 2
```

Two scopes and five rules in the source; nothing in the copy. Then
`grep -rniE "copy a project|copying a project|Project#copy" docs/ README.md
CHANGELOG.md` and `grep -rn "Redmine::Hook\|model_project_copy" lib/ app/ init.rb`
— both empty. It is an unconsidered gap rather than a recorded decision.

**Suggested direction**

Class B, and the two options are genuinely different products. **Copy it**: hook
`model_project_copy_before_save`, and copy the scopes and the rules for the
trackers the copy actually has — the machinery exists, `ScopeCopier` and
`copy_generic_to_project` already do this shape of work for the role and tracker
duplication paths, which is the precedent. **Or say it**: one paragraph in the
README's *Upgrading* neighbourhood and one line on the copy form, stating that a
copy starts from the generic workflow. Copying is the less surprising of the two
and matches what duplicating a role already does; whichever is chosen, the
decision belongs in `docs/DECISIONS.md`, because the present state is silence
rather than a choice.

**Resolution:** fixed — **copy it**, which is what the finding recommended and
what duplicating a role or a tracker has done since 0.1.0. Logged as a Class B
choice in `docs/DECISIONS.md` with both options, what A costs, and the
recommendation; A is in place and is reversible from the screen.

`Hooks::ProjectCopyHook` is the plugin's first and only `Redmine::Hook::Listener`
and does nothing but check its arguments; `Services::ProjectWorkflowCopier` does
the work. It copies the scopes and then the rules those scopes make visible, for
the trackers the *target* has, in two INSERT … SELECT statements per rule type
rather than a round trip per row. An own *empty* workflow arrives as an empty one
(INV-3); a rule row with no scope is left behind, because the resolver ignores it
where it is now; a target that already carries a scope of its own is not touched
at all. The generic workflow and the source are untouched (INV-1) and every
statement names a project_id (INV-4).

The one thing the finding did not raise and the fix had to answer: `docs/design.md`
counts the write paths that take scope rows before workflow rows, and that count
was **four**. This is a fifth. It takes no `SELECT … FOR UPDATE` and it says so
in the same paragraph, with the reason — the target was created a few statements
earlier in the same transaction and no other request has seen its id. The count
moved from four to five in the same commit, because that document already records
how a counted claim with a path missing produced finding F01 of 2026-08-27.

Red on the old code, measured rather than assumed: with the listener's body
replaced by `nil` and nothing else changed, **3 of the 11** new examples fail —
the scope and rules case, the own-empty case, and the one that compares the
effective status list of the copy against the source's (`[1, 3]` expected,
`[1, 2]` returned, the copy having fallen back to the generic workflow). The
remaining eight are the copier's own cases and the controls, which cannot fail
against code that has no copier. Documented in `README.md`, `CHANGELOG.md` (an
`### Added` bullet of its own) and `docs/design.md`'s table of Redmine's seams.

---

### F02 — Three query services build a relation on `workflows` with no `project_id`, so INV-4's own grep comes back dirty

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** code-quality
- **Where:** `lib/redmine_project_workflows/services/status_list_query.rb:69`,
  `lib/redmine_project_workflows/services/permission_query.rb:18`,
  `lib/redmine_project_workflows/services/transition_query.rb:25`
- **Invariant touched:** INV-4, in its letter rather than its effect

**What is wrong**

Each of the three holds a base relation narrowed by tracker and status but not by
project, and adds the `project_id` afterwards on every branch:

```ruby
base_scope = WorkflowPermission.where(tracker_id: issue.tracker_id, old_status_id: old_status_id)
scopes << base_scope.where(project_id: issue.project_id, role_id: overridden_role_ids) if …
scopes << base_scope.where(project_id: nil, role_id: global_role_ids)                  if …
```

I read all three and **no branch executes the base relation** — every path adds a
`project_id` before `to_a` or `pluck`, so nothing today mixes the two populations.
The defect is not a wrong answer; it is that this is precisely the shape
`WorkflowPopulations` was extracted to eliminate, and its own comment says why:
*"a helper that handed back a relation narrowed by tracker alone … would be INV-4's
discipline with one more place to get it wrong — and a relation that mixes both
populations if anything ever executed it."* That argument applies unchanged here.

**Why it matters**

Two ways, both about the next person rather than about today. `CLAUDE.md`'s
forbidden-constructs table says "a `workflows` query with no `project_id`
predicate" is forbidden and points at the query services as the remedy; a reviewer
grepping for exactly that finds three hits inside the remedy and has to read each
one to clear it — which I did, and which the next reviewer will do again. And a
future edit that adds a fourth branch, or moves a `pluck` one line up, turns a
safe pattern into a silent population mix with no test that would notice: these
are the two hottest paths in the plugin, and a query that quietly read another
project's rules would show up as a wrong status list, not as an error.

**How I verified it**

`grep -rnE "Workflow(Rule|Transition|Permission)\.(where|find|all|count|pluck)"
app/ lib/ --include=*.rb | grep -v project_id` returns five hits; two are
multi-line calls whose `project_id` is on the following line, and the three above
are real base relations. Read each in full to confirm every branch narrows before
executing.

**Suggested direction**

Either route the three through `WorkflowPopulations` where the split is the same
one it already knows, or — where the extra conditions make that awkward — keep the
local shape but make it unexecutable rather than merely unexecuted: build the two
finished relations in one private method that cannot return a half. A comment
naming these three as deliberate, the way `CLAUDE.md` names
`copy_one_with_projects`, is the cheap answer and is better than nothing; it is
not as good as making the shape impossible.

**Resolution:** fixed — the shape is impossible rather than merely commented,
which is the half of the suggested direction the finding itself called the
better one.

`TransitionQuery` and `PermissionQuery` now build both populations with
`WorkflowPopulations`, which is what it was extracted for, and add everything
else — the status, the author/assignee condition — to what comes back rather than
to the halves. `StatusListQuery` keeps its local shape, because the bulk pair
grouping does not fit `WorkflowPopulations`, but its `base_scope` is gone: the
one method that builds a relation there takes the project_id as a **positional**
argument, exactly as `WorkflowPopulations.relation` does, so a relation without
one cannot exist in the file even for a line.

`spec/plugin_conventions_spec.rb` now greps for the construct. It checks the
**statement** rather than a window of lines — the match is grown until its
parentheses balance — so a base relation assigned on one line and given a
project_id by a later statement does *not* clear it. A three-line window did
clear it, which is worth recording: the first version of this test passed against
the very shape it exists to reject.

One behaviour had to be preserved and was nearly lost. `WorkflowPopulations`
answered `[]` for a blank project_id, and an issue with no project yet reads the
**generic** workflow — the choice `Issue#tracker=` records in its own comment.
Since no project means no scope can exist, the Resolver already answers "nothing
overridden", so dropping that guard is the whole change and the relation still
carries an explicit `project_id: nil`. Two examples pin it, in
`transition_query_spec.rb` and `permission_query_spec.rb`.

Red on the old code: with the old `base_scope` put back in `PermissionQuery`
alone, the conventions example fails naming
`lib/redmine_project_workflows/services/permission_query.rb:26`; with the blank
project_id guard put back in `WorkflowPopulations`, the two new nil-project
examples fail and nothing else does. No answer changed anywhere: 852 examples
green on 7.0 and on 5.1.

---

### F03 — The diagram's accessible label counts the *New issue* node as a status and Redmine's fallback as a transition

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** accessibility
- **Where:** `app/helpers/project_workflow_graphs_helper.rb:73`
- **Invariant touched:** none

**What is wrong**

```ruby
l(:text_project_workflow_graph_aria, statuses: layout.nodes.size, transitions: layout.edges.size)
```

`layout.nodes` includes the entry node, which is core's `old_status_id = 0`
pseudo-status and not a status an issue can sit in — the query's own `Node` struct
has `entry?` precisely to tell them apart, and the dead-end diagnostic already
excludes it for exactly this reason. `layout.edges` likewise includes the fallback
arrow added for F01, which is Redmine's behaviour rather than a stored transition;
the drawing distinguishes it with a dotted stroke and the table's condition cell
calls it *Redmine's own fallback*, so the label is the one place that counts it as
an ordinary move.

**Why it matters**

A workflow of six statuses is announced as seven, and this is the **first and
often the only** thing a screen-reader user hears about the picture — the sentence
that decides whether they read on into the table or move past. Getting a count
wrong there is a small error in the one place where there is no second chance to
see it. Sighted readers never meet it.

**How I verified it**

In Chromium on a live project with six statuses and five stored transitions plus
the entry rule:

```
svg role=img aria-label="Diagram of this workflow: 7 statuses and 5 transitions.
                         The same information is in the table below."
knopen: New issue, New, In Progress, Resolved, Feedback(band), Closed, Rejected
```

Seven nodes, six statuses. The rest of the accessibility check came back clean:
`role="img"`, twelve `<title>` elements, a sane heading hierarchy, a labelled role
selector, and the table twin with real headers.

**Suggested direction**

Count what the words say: statuses excluding the entry node, transitions excluding
the fallback. If the fallback is worth mentioning it deserves its own clause
rather than being folded into the count — a screen-reader user has as much use for
"and Redmine's own starting point" as a sighted one has for the dotted arrow. The
existing key takes two interpolations; a third, or a second sentence, is the whole
change, in eight locale files.

**Resolution:** fixed — both counts now count what the words say, and the
fallback is given a clause of its own rather than dropped.

`project_workflow_graph_aria_label` counts `layout.nodes` excluding the entry
node and `layout.edges` excluding the fallback, and appends
`text_project_workflow_graph_aria_fallback` when there is one. A separate locale
key rather than a third interpolation on the existing one: the clause only exists
on the workflows that have a fallback, and a single sentence that has to read
well with and without a clause is harder to keep honest in eight files than two
short ones. All eight are translated; `fr` and `pl` were reworded after drafting
to use the same words for *fallback* and *issue* their own legend sentence
already uses.

Worth naming, because it reverses something: `docs/STATE.md` recorded the
previous session's deliberate choice to count the arrows, on the grounds that the
number of arrows is what a reader of the picture wants. That argument does not
survive the sentence saying *transitions*, and it never covered the entry node
being counted as a status, which is the half of this finding that is simply
wrong.

Red on the old code: with the two counts put back to `layout.nodes.size` and
`layout.edges.size`, **2 of the 3** new examples fail on the rendered page — a
three-status chain announced as four statuses and three transitions where the
sentence claims three and three, and a two-status workflow with a fallback
announced as three and two where it should be two and one. The third example (a
workflow with no fallback says nothing about one) is the negative case and
correctly stays green.

---

## Checked and found sound

The substance of this run. Recorded so a later session does not re-derive it, and
so the go-live decision rests on measurements rather than on confidence.

### The five findings of the first run

| Finding | Re-tested how | Result |
| --- | --- | --- |
| **F01** entry-node fallback | a Redmine seeded with nothing but `redmine:load_default_data`, `WorkflowTransition.where(old_status_id: 0).count == 0` | band empty (was every status), one dotted fallback arrow, diagnostics read *"Every status … can be reached from a new issue and has a way out"* |
| **F02** mixed-scope sentence | Manager with own rules, Developer own-empty, one reader holding both | panel now says *"At least one of your roles here … Another of your roles may still permit some"*, and the status list offers exactly what the Manager workflow allows |
| **F03** dense workflow | Redmine's default complete graph | detected, folded into `<details>` with *Show the diagram anyway*, SVG not rendered until asked, sentence explains why a diagram adds nothing |
| **F04** the band | a two-status chain nobody can reach | laid out in its own two layers (x=14 and x=224), drawn as a forward arrow rather than a bow, nothing clipped, nothing overlapping |
| **F05** adjacent links | the settings tab | the row renders as *Give own workflow (copy of the generic one)* &#124; *Give own empty workflow* — the separator is present in both pairs |

### Data lifecycle

| Checked | Result |
| --- | --- |
| Delete a project | scopes and project rules gone through the real foreign key; **0 orphan scopes, 0 orphan rules** measured against `Project.select(:id)` |
| Delete a role | its scopes and its project rules gone; nothing left behind |
| Delete a tracker | same |
| Delete an issue status | core removes its rules in **both** populations (correct — a deleted status can be referenced nowhere), scopes untouched and still meaningful |
| **Duplicate a role** (`RolesController#create` → `copy_workflow_rules`) | 90 generic + **10,805 project rules + 181 scopes** copied; source unchanged; the copy resolves to the *same* graph as the source (`own`, 31 edges). The INV-4 exception does what `CLAUDE.md` says it does |
| **Duplicate a tracker** | same shape, verified separately |
| Core's own `WorkflowRule.copy` | stays generic-only, as the patch comment says it must. My first measurement called this instead of the real path and briefly looked like a defect; it is not |

### Project state, access and concurrency

| Checked | Result |
| --- | --- |
| **Closed** project | all three reads 200; **all four writes 403** (matrix save, enable, inherit, clear); the settings tab renders with **zero** write links, so the UI offers nothing it cannot honour |
| **Archived** project | every route 403, reads included |
| **Anonymous** on a public project | issue page renders; the workflow panel renders for the Anonymous role only; the diagram, the settings tab and the inventory all bounce to the login form. A bare cross-origin `GET` of the panel is refused by Rails with **422 InvalidCrossOriginRequest** — the script-tag leak vector is closed, and the plugin has not disabled forgery protection anywhere |
| **22 concurrent writers** on one (project, tracker, role) | no errors, **0 duplicate rows**, generic workflow still exactly 144. The residual race `docs/DECISIONS.md` records on 2026-08-26 did not reproduce; `rake redmine_project_workflows:deduplicate_workflow_rules` was also exercised and cleared 16,200 duplicates I had created myself with a double-run of a load script |

### Scale — 123 projects, 542 scopes, 16,205 project rules

| Screen or query | Time |
| --- | --- |
| Resolver point lookup (the issue-form hot path) | **0.24 ms cold, 0.006 ms cached** |
| `Issue#new_statuses_allowed_to` | **3.1 ms** per call, cold every time |
| Inventory: count / page 1 / page 21 | **0–4 ms / 5–7 ms / 4–5 ms** (paginated; the product is never built) |
| The whole graph query | **4–5 ms**, and **7 queries flat** — not per node and not per edge |
| Inventory page over HTTP | 164 ms · deviations-only 160 ms · page 21 187 ms |
| Generic matrix / project matrix / diagram / settings tab | 247 / 249 / 168 / 255 ms |

### Reversibility, on the populated database rather than an empty one

`rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0` against
123 projects, 542 scopes and 16,205 project rules:

- `workflows.project_id` gone, `project_workflow_scopes` gone, the foreign key
  gone, the plugin's five `schema_migrations` rows gone
- `workflows` back to core's own five indexes
- **the generic workflow intact at exactly 144 rules**; the project rules went with
  the column, which is what should happen
- projects, issues and users untouched
- migrating up again restored the column, the table, the foreign key and the two
  composite indexes

The README already calls uninstalling a data change, tells the operator to take a
backup and says there is no way back. That is the right warning and it is in the
right place.

### Invariants and the forbidden-constructs table

| Checked | Result |
| --- | --- |
| INV-1 write isolation | a project write left the generic workflow at 144 through every concurrency and copy test |
| INV-2 | `insert_all` appears only in `TransitionWriter` and `PermissionWriter`; `ScopeWriter` explains at length why it uses `create!` instead |
| INV-3 | all three states still distinguishable on both screens, and F01's fallback deliberately does **not** make an own-empty workflow read as a filled one (`empty_workflow?` counts `stored_edges`) |
| INV-4 | holds in effect everywhere; three base relations grep dirty and are safe — that is F02 |
| INV-8 | verified above, on real data |
| INV-9 | fifteen overrides in twelve files; `CLAUDE.md`, `docs/design.md` and the spec comment agree. WP9 and its fixes added no Deface anchor |
| CSRF | nothing skips forgery protection; no `accept_api_auth`; the one cross-origin probe is refused by Rails |
| `html_safe` | still only on literal constants, and the new `project_workflow_graph_dash` helper exists specifically to keep it that way |
| Locales | **all eight files at 117 keys, exact parity**. The six non-authoritative ones read as real translations of the new WP9 strings — German, French, Spanish, Italian, Polish and Portuguese all render the dense-workflow sentence idiomatically rather than as English or as a literal gloss |
