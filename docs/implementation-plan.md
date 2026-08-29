# Implementation plan — WP0..WP9

> Work in this order. Each package is one commit (or a small run of them) on
> `claude/dev`, green at every commit. `docs/design.md` describes the target;
> this file describes the route.

## Reference

- **Decision:** [`adr/ADR-001-scope-model.md`](adr/ADR-001-scope-model.md)
- **Design:** [`design.md`](design.md)
- **Choices already made:** [`DECISIONS.md`](DECISIONS.md) — do not re-open one
- **Findings this plan answers:** [`review/findings/`](review/findings/)

## Progress

| Package | Title | Status |
| --- | --- | --- |
| WP0 | Immediate repairs | **done** |
| WP1 | Scopes: table, model, resolver, backfill | **done** |
| WP2 | Correctness at the core seams | **done** |
| WP3 | Summary and inventory | **done** |
| WP4 | Project settings tab and permissions | **done** |
| WP5 | Bulk editing in the matrix | **done** |
| WP6 | Compare, audit, undo | **done** |
| WP7 | Documentation, locales, release | **done** |
| WP8 | Status help and the transition map on the issue form | done |
| WP9 | The workflow as a drawing, per role | **done** |
| — | *WP0..WP9 delivered the plugin. WP10..WP16 are the hardening track that makes it releasable.* | |
| WP10 | Ecosystem safety: the name collision, the version probe, four confirmed defects | **done** |
| WP11 | Compatibility as an object (ADR-002) | **done** |
| WP12 | Owned administration screens (ADR-003) | **in progress** — steps 1-3 done |
| WP13 | One write-coordination service, and bounded bulk writes | in progress — the lock and the bulk bounds are done; the selector remains |
| WP14 | The remaining defect backlog | planned |
| WP15 | The test debt three reviews named | planned |
| WP16 | Release engineering | planned |

---

## WP0 — Immediate repairs

Everything here is independent of the data model and none of it has to be
redone later.

- The project selector renders the SVG sprite core expects since 6.0, behind a
  `respond_to?` fallback for 5.1. Without it `toggleMultiSelectIconInit()`
  calls `updateSVGIcon(undefined, …)` and the page's JavaScript initialisation
  aborts. *(claude F04)*
- Patches move from `after_initialize` to `to_prepare`, with an idempotent
  prepend guard. *(claude F05)*
- `return if performed?` after every `load_project_options`, plus strict
  validation of target project ids: only `global` or digits, loaded in one
  query, de-duplicated, reported as a translated validation error. *(external
  F03)*
- `project_context?` derives from the presence of plugin parameters rather than
  from a non-empty project list, so "copy to the generic workflow only" stops
  falling through to core. *(external F02)*
- Server-side whitelisting of `rule`, `field_name` and status ids in both
  writers — this restores validations that core had and the plugin's routing
  removed. *(external F05)*
- The `Thread.current` cache fallback is removed; `RequestStore` only.
  *(external F09)*

**Done when** the matching characterization examples have been inverted and
moved out, and 6.x/7.0 show no JavaScript error on the workflow page.

**Done.** All six, with two corrections found on the way. `to_prepare` is the
wrong hook for a Redmine plugin — Redmine already loads `init.rb` inside one,
and `config.to_prepare` there is a silent no-op that disables the plugin
entirely; `apply_patches` is called in the body of `init.rb` instead. And
`RequestStore` is not available on every supported version, because Redmine 7.0
dropped the gem; the cache is `ActiveSupport::CurrentAttributes`. See the
`Resolution:` lines of claude F04/F05 and external F02/F03/F05/F09.

## WP1 — Scopes: table, model, resolver, backfill

- Migration creating `project_workflow_scopes` as specified in `design.md`,
  with the backfill: every (project, tracker, role) that has rules gets a scope
  of the matching type. Reversible, and tested up → down → up.
- `ProjectWorkflowScope` model with validations and a lookup by
  (project, tracker, role, rule type).
- `Resolver`, `TransitionQuery`, `PermissionQuery` and `StatusListQuery` decide
  on scopes instead of on row existence. `override_active?` becomes a lookup on
  the current project, cached per request.
- The writers create or keep a scope on a project write and never remove one
  implicitly.
- The three actions from `design.md`, wired into the admin screens: enable
  (copy or empty), return to inheritance, empty the matrix.

**Done when** the characterization examples about override semantics have been
inverted: an empty scope allows no transition, and a project rule no longer
silently converts the whole tracker/role to project control without a scope
saying so.

**Done.** `spec/characterization/override_semantics_spec.rb` is gone; its
examples are inverted in `spec/models/override_semantics_spec.rb`, joined by two
new ones for the empty state and for INV-6. Two things came out differently from
the plan:

1. **The unique index on the scope table ships here, not in WP2.** It is part of
   the table `design.md` specifies, and the backfill has to produce unique rows
   anyway. WP2's remaining index work is the one on `workflows` itself.
2. **The core fallback had to go entirely.** The plan said the resolver would
   decide on scopes; narrowing `override_active?` from "any project anywhere" to
   "this project" would then have sent every inheriting project through core's
   own query — which carries no `project_id` predicate and would have handed it
   other projects' rules. `Issue#new_statuses_allowed_to` and
   `#workflow_rule_by_attribute` are now always answered by the plugin. See
   `DECISIONS.md`.

## WP2 — Correctness at the core seams

- `Project#rolled_up_statuses` loses the role filter and computes effective
  statuses per project across the tree, then unions. Fixes both the empty
  status filter for member-less projects and the incomplete subproject
  handling. *(external F08)*
- The two `Issue` call sites that consult `Tracker#issue_status_ids` become
  project-aware; the tracker method itself stays a global union. *(claude F02 —
  see its `Resolution:` for why the obvious fix is the wrong one)*
- `WorkflowRule.copy` carries project rules and their scopes, so copying a role
  or tracker produces a working copy. *(claude F03)*
- ~~Unique index on the scope table~~ — delivered in WP1's migration. For the
  workflow rows themselves: an idempotency test, and a unique index only where
  the canonical key is unambiguous, with a cleanup step first. *(external F06)*
- Walk the remaining core queries against `workflows` (default data loader,
  status deletion) and record the outcome in `design.md`.

**Done when** `spec/characterization/` holds only the summary-page example.
*(Corrected: this line said "is empty". Three of the four characterization
examples belong to WP2; the fourth is the summary page's count, which is
claude F01 and therefore WP3's. WP2 cannot empty the directory.)*

## WP3 — Summary and inventory

- `WorkflowsController#index` counts per scope instead of mixing populations,
  with a project selector above the existing grid. Default: generic, so the
  page behaves as before for anyone who does not use the plugin. *(claude F01)*
- An inventory view: one row per (project, tracker, role), columns for
  transitions and field permissions, counts, and the state as a **text** label
  — *Own workflow*, *Inherits generic*, *Own empty workflow* — with colour only
  supporting it.
- Filters on project, tracker, role, rule type, and "deviations only" versus
  everything. Default: deviations only.
- An empty state with a sentence and two actions rather than an empty table.
- Rows link into the existing matrices, pre-filled.

**Done when** `spec/characterization/` is empty — the summary-page example is
its last one.

**Done.** `spec/characterization/` no longer exists. The summary page counts per
scope and carries the selection into its count links; the inventory is a screen
of the plugin's own at `/project_workflow_inventories`, reached from core's
action menu and from the summary page.

Three things came out differently from what this bullet list assumed:

1. **The count cell had to be replaced, not only the count.** Core builds the
   link with a bare `{:action => 'edit', :role_id => ..., :tracker_id => ...}`,
   which carries no project, so a filtered page would have shown one workflow's
   numbers and linked to another's. The cell is now the plugin's markup, and
   because 5.1 and 6.0 draw an empty cell differently the shape comes from
   `VersionHelper`. Without a project selection the URL stays byte-identical to
   core's.
2. **The inventory counts the project's own rules, never the generic ones.** An
   inheriting row therefore reads `0`, and the *label* — not the number — is
   what says the generic workflow applies. The alternative, showing the generic
   count on an inheriting row, would have put a number in the cell that does not
   match the matrix the cell links to.
3. **Deleting the last characterization example uncovered five specs that
   passed for the wrong reason.** That file was the only one loading the
   `enumerations` fixture, and five specs that create an `Issue` were relying on
   it being in the database. They now declare it themselves.

## WP4 — Project settings tab and permissions

- Permissions `view_project_workflow_rules` and `manage_project_workflow_rules` under the
  issue tracking module. Managing includes enabling and returning to
  inheritance.
- A tab in project settings, via a patch on
  `ProjectsHelper#project_settings_tabs`, listing per tracker and role the
  current state with the three actions. Editing opens the matrix.
- The plugin's own controller, authorizing per project. The matrix is reused
  but narrowed to the trackers enabled in the project and the roles with
  members there.
- The generic workflow is visible read-only, as a reference.

**Done when** authorization specs cover: no permission, view only, manage, and
an attempt to write to another project. This is the only place where
non-administrators write workflow data; it carries the heaviest test coverage.

**Done.** All four, plus the read-only reference. Two things were decided on the
way. The project matrix edits **one** tracker and one role at a time — the
settings tab is the list, and one combination per matrix keeps every cell a
plain yes or no instead of needing the administration screens' third "no change"
state. And saving a matrix while the project still inherits is **refused**:
the writers create the scope a project write implies, so accepting it would
collapse "enable" into "save". Finding G03 was looked at and deliberately left
as core behaves; it is an open choice in `DECISIONS.md` with a recommendation.
The per-project entry point to the inventory is the tab itself, which shows the
same rows for one project.

## WP5 — Bulk editing in the matrix

- Mixed-value cells get the same CSS classes and data attributes as ordinary
  checkboxes, so Redmine's own row and column toggles reach them. *(claude F06)*
- Explicit per-row and per-column actions Yes / No / Unchanged — toggling is
  not the same as setting to No, and setting to No is the case that needs it.
- The size of the selection shown above the matrix, and a confirmation once an
  action would touch more than a configured number of workflows.
- Keyboard operation, visible focus and `aria-label`s from the start.
  "Unchanged" gets clearer wording and a legend.

**Done, with one correction and one deferral.** The first bullet's premise does
not hold: the classes are necessary and are now on the mixed cell, but core's
toggle selects on `input[type=checkbox]:not(:disabled).new-status-N` and nothing
of that shape can match a `<select>`. Core's toggle is therefore left exactly as
it was and the plugin adds three actions of its own, which select on the class
alone and reach both kinds of control. "Unchanged" reuses core's own
`label_no_change_option` so that the cell and the action on it read the same; the
clearer wording is the legend. The **field-permissions** matrix keeps only core's
`»` copy control — its cells are four-valued rather than yes or no, and core has
no row or column toggles there to repair. Jan answered that one **A** on
2026-08-26 — leave it as it is — so it is settled rather than open; see
`docs/DECISIONS.md`.

## WP6 — Compare, audit, undo

- A "project versus generic" view showing which cells differ, reachable from
  the inventory and from the matrix.
- `created_by_id` / `updated_by_id` maintained on every write path and shown in
  the inventory and the project tab.
- Bulk actions change the screen first, with a counter and an undo control;
  only Save writes.

Out of scope: workflow templates, rectangle and drag selection.

**Done.** All three, and finding **G02** was read with them and left standing --
see below. Four things came out differently from what this list assumed:

1. **The audit columns needed a stamp, not a column.** WP1's migration already
   created all four; what was missing was that `ScopeWriter.ensure_scopes` --
   the method every project matrix save goes through -- deliberately left an
   existing scope alone. `touch_scopes` is the stamp, and the two halves are kept
   apart on purpose: `created_*` records who decided the project runs its own
   workflow, `updated_*` who last changed the rules. The sentence on screen is
   core's own `authoring` with `label_updated_time_by`, so it needed no locale key
   of its own.
2. **The comparison compares grids, not rows.** Core's transitions screen draws
   three grids and partitions the rows into them with
   `reject { author || assignee }`, `select(&:author)` and `select(&:assignee)` --
   so a row with **both** flags set is in two grids at once. Comparing by grid is
   what makes the answer match the screen. Field permissions get a third state
   transitions cannot have: both sides speak and disagree.
3. **"Bulk actions change the screen first" was already true; the counter and the
   undo were the gap.** WP5's actions never wrote anything -- only Save does --
   but nothing on the page said so, and one click could change a hundred cells
   with no count and no way back short of reloading. The undo is a stack, so
   repeated actions step back one at a time, and it restores the value each
   control held *before* the action rather than the value the page was opened
   with; those are the same thing only for the first action.
4. **A new controller action is 403 for everybody until `init.rb` names it.**
   Including administrators, and the symptom is a forbidden page rather than an
   "unmapped action" error. `spec/plugin_conventions_spec.rb` now asserts
   structurally that every action of `ProjectWorkflowsController` is named by at
   least one of the two permissions.

**G02 stands, and WP6 is where it was to be settled.** A cross-project bulk
tracker change is two queries per distinct project where core is one for the whole
selection, because core hands the same `Tracker` instance to every issue and
memoises on it. WP6 confirms WP2's reasoning rather than overturning it: the
plugin's request cache is keyed by (project, tracker), which is the narrowest key
that can be correct -- a per-`Tracker` memo is exactly the project-blind cache
INV-4 forbids. Collapsing the repeats across projects would mean resolving the
whole selection up front, which puts a query on every single-issue save to save
one on a bulk move. Left open, with its reasoning now twice-examined.

## WP7 — Documentation, locales, release

- README: that a scope **replaces** the generic workflow, what the three states
  mean, what "generic" is, and what happens with several projects selected.
  *(external F11)*
- All new strings in `en` and `nl` by hand; the other six locale files carry
  the keys.
- Terminology fixed: **Generic workflow**, **Own workflow**, **Inherits the
  generic workflow**.
- Version-conditional code consolidated into one helper.
- Version bump, CHANGELOG, and an upgrade note about the backfill.
- Work down `.rubocop_todo.yml` where the fix is mechanical and safe.

**Done.** Three of the six bullets were work; **three were already satisfied** and
are recorded here rather than pretended. The review caught that the first version
of this note accounted for only five of the six and quietly dropped the one about
locales — in the package named *Documentation, locales, release*.

1. **The terminology was already fixed.** *Generic workflow*, *Own workflow* and
   *Inherits the generic workflow* are what WP3, WP4 and WP5 used as they went,
   in all eight locale files. Nothing to change. (`label_project_workflows_global`
   is the one place the *key* still says "global" where its value says "Generic";
   renaming a key across eight files and the code to fix a name no user sees is
   not worth the churn.)
2. **Version-conditional code was already in one helper.** All five things that
   differ across the 5.1 → 6.0 SVG-sprite break go through
   `RedmineProjectWorkflows::VersionHelper`; a grep for `respond_to?` outside it
   finds only duck-typing on request parameters.
3. **The locale bullet was owed nothing.** WP7 adds no user-visible string of its
   own, and every string WP3 through WP6 added was written into `en` and `nl` by
   hand and into the other six as it went — `spec/locales_spec.rb` asserts parity,
   and all eight files carry the same 74 keys.

The three that were work:

4. **The README's `What to know before you install it`** — F11, and more than it
   listed. Plus a section on what a selection of several projects does when you
   save, which is the case that writes the most rules from one click, and an
   **Upgrading and uninstalling** section: what the backfill does, and that
   `VERSION=0` deletes every project-specific rule.
5. **0.1.0, with a CHANGELOG that reads as a release rather than a diff**, and
   the entries reordered newest-first.
6. **The declared minimum moved from Redmine 5.0 to 5.1.** Nothing had ever
   tested 5.0 and the README said so, which is a strange thing to declare and
   then warn about. Refusing an install the plugin cannot vouch for is the safer
   direction for an alpha that rewrites workflow data; it is one line to revert.
7. **`.rubocop_todo.yml`: 198 offences in 21 files down to 48 in 8**, and the
   file is annotated by hand rather than generated and left. What remains is
   three groups, each named in the file's own header: the four patch files whose
   method bodies are core's (refactoring them for a metric would destroy the
   property that lets you diff them against a real checkout), `insert_all` and
   `update_all` in the writers (INV-2 — the writer *is* the validation), and
   three single offences where the cop's fix would be wrong. One offence turned
   out to be worth fixing rather than excluding:
   `TransitionWriter.transition_row` took seven positional parameters ending in
   two booleans, which is exactly the shape `Metrics/ParameterLists` exists to
   catch, and is now keyword arguments.

**The WP7 review found six real defects and all six are fixed.** Three were in
the uninstall instruction — the one command in the README that destroys data:
it described the down migrations in the wrong order, and it omitted `RAILS_ENV`
from every migrate command, which Redmine's plugin task defaults to
*development*. The others: the plugin's biggest install-time behaviour change
(routing core's own `replace_transitions` / `replace_permissions` through the
writers, which narrows what a *generic* save accepts on every installation) was
in neither the README nor the CHANGELOG; one `.rubocop_todo.yml` annotation
excused a long line the autocorrect had itself created; another filed
`workflow_rule_patch.rb` under INV-2 when that file uses `connection.insert` and
is not a writer; and F11 ended up marked both fixed and open.

---

## WP8 — Status help and the transition map on the issue form

New requirement, raised 2026-08-26: *when editing an issue a clickable info icon
shows the meaning of every available status, and — as Jira does — a flowchart of
the possible status changes.* `design.md` carries the target; this was the route.
**Done**: `Services::TransitionMapQuery`, `ProjectWorkflowMapsController`, one
Deface override on `issues/_attributes` (INV-9 count 13 → 14), and 68 examples,
green on 5.1, 6.1 and 7.0.

**The first half already exists in Redmine, and this plugin is what makes it
correct.** `issues/_attributes.html.erb` renders an `icon-help` link next to the
status select on 5.1, 6.1 and 7.0, opening core's `#issue_statuses_description`
modal: a `<dl>` of status name and `IssueStatus#description`, each name clickable
to apply that status. It lists `@allowed_statuses`, which is
`Issue#new_statuses_allowed_to` — the method this plugin replaces in full — so it
already describes the project's own effective workflow. It renders only when at
least one available status has a description, which is why an installation that
has never filled them in believes the feature is absent. So this half is:

- a spec asserting the modal names the project's own statuses and **never** a
  status only another project's rules reach (INV-4), on all three versions;
- a spec asserting an empty own workflow yields no modal rather than the generic
  list;
- a README paragraph pointing administrators at *Administration → Issue statuses
  → Description*, because the icon is invisible until they use it.

**The second half is new.** `Services::TransitionMapQuery`: for one (project,
tracker, role ids) triple, the effective transitions as nodes and edges, each
edge carrying its condition — unconditional, author-only, assignee-only — and
core's `old_status_id = 0` *new issue* pseudo-status as the entry node. One scope
lookup and one transitions query, both with an explicit `project_id` (INV-4).

Then:

- The plugin's own controller action, loaded lazily into core's `#ajax-modal` so
  an ordinary issue edit runs no extra query (G6). Authorization: the issue
  through `Issue.visible`, or for an unsaved issue the project plus `add_issues`.
  The tracker on the new-issue form arrives as a parameter and is matched against
  the project's own trackers, never queried (INV-7).
- One Deface override on core's `f.select :status_id` expression — byte-identical
  in 5.1, 6.1 and 7.0, unlike the help icon beside it, which 6.0 turned into a
  sprite. The INV-9 count rises, in `CLAUDE.md`, `design.md` and the spec's
  comment, with an assertion in `spec/integration/deface_overrides_spec.rb` that
  only this override can satisfy.
- **The panel says which workflow it is describing.** Raised by Jan on 2026-08-26
  while reviewing this spec, and it is the first thing somebody debugging *why can
  I not close this issue* needs. Nothing on the issue form says it today: core has
  no concept of a project workflow, and WP8 is the first thing the plugin puts on
  that form. In the words the rest of the plugin already uses (**INV-3**) — *Own
  workflow*, *Own empty workflow*, *Inherits the generic workflow* — **per role**,
  because resolution is per role and the result is a union, with a link to where it
  is edited that is gated by permission (the project's Workflow tab, or
  Administration → Workflow for an administrator, or no link at all rather than one
  that answers 403). The *own empty workflow* case is the one that stops being a
  convenience: an empty status dropdown with no explanation is indistinguishable
  from a broken plugin. It costs nothing — the panel resolves the scope to build
  the transition list anyway, and that is one cached point lookup.
- The renderer: **the local "from here" view alone**, answered **C** by Jan on
  2026-08-26. The status the issue is in, the statuses it can move to, what each
  move requires — anyone with the role, only the author, only the assignee — and
  the statuses that can lead into this one. A `table.list` of
  *from → to → condition*, which needs no layout pass and is readable by
  anything. **No drawing**: a layered SVG diagram (option A) stays buildable on
  top of this later, because A is exactly this data with a layout pass added.
- The honesty clause from `design.md`: the map says what the workflow allows, the
  dropdown stays the authority for what may be done now, and an edge the
  dropdown withholds carries the reason — core's own `transition_warning`
  sentence where core has one.
- Strings in `en` and `nl` by hand, the other six locale files carrying the keys.

Out of scope: the bulk-edit form (a selection spans projects and trackers, so one
map would be a lie about most of it), the issue show page (worth doing, and a
scope of its own — the reader there may not be able to change anything), and
editing a status description from the map.

**Done when** a project with its own workflow shows a map that matches its own
matrix, an inheriting project shows the generic one, neither can see the other's,
the panel names which of the three states it is describing for each of the
reader's roles, and the specs above are green on all nine CI cells.

---

## WP9 — The workflow as a drawing, per role

New requirement, raised 2026-08-28: an ex-Jira user misses the picture with the
arrows and reads its absence as Redmine falling short. The **local** view shipped
in WP8 answers "what may I do from here"; what is missing is the whole flow of a
project's workflow in one image. This package builds it — and builds it so that
it says more than Jira's does, because Redmine knows something Jira does not:
which role the reader holds.

`docs/DECISIONS.md` (2026-08-28) carries Jan's three answers, and they set the
shape of everything below. This does **not** re-open the 2026-08-26 answer of
**C** for WP8's panel: C said the panel gets the local view and no drawing, and
said in the same breath that A stays buildable on top of it. That is exactly what
this is. The panel stays as it is.

**What is better than Jira, and why it is nearly free here.** Jira draws one
diagram per issue type: permissions and conditions live in a dialogue behind the
arrow, so the picture shows the transitions *somebody* may make, not the ones
*you* may make. Redmine's workflow is per (tracker × role) in the table itself,
so a role selector is not a trick — it is the data model becoming visible. Three
consequences, and they are the package's reason to exist:

- **Per role**, defaulting to the reader's own roles — the union the status
  dropdown is built from (INV-5: the roles' rules are a union, the scopes are
  not merged).
- **Unreachable and dead-end statuses are named, not merely drawn.** A status no
  role can reach, or one with no way out, is a real defect in a workflow. Jira
  draws it and says nothing. This is the part a workflow administrator will
  actually use.
- **An own empty workflow draws as an entry node and nothing else**, with the
  sentence WP8 already has. The three states of INV-3 stay tellable apart in the
  drawing as they are everywhere else.

### Where it lives, and why not in the modal

**On the project screen, beside the matrix** — answer **A** to choice 1. Measured
on the model: five layers of a six-status workflow are 1016 px wide, and one more
status adds about 210 px; Redmine's `#ajax-modal` is about 900 px. Scaling to fit
puts the status names below legibility. So the drawing gets a screen with room,
and the issue form keeps the panel it has: short, local, one question answered
fast. That split also matches the use — on an issue you want to know what you may
do now; on the project screen you want to understand the whole thing.

**Behind `view_project_workflow_rules`** — answer **A** to choice 2. The whole map shows
what *other* roles may do, which is project configuration rather than information
about one issue. The WP8 panel keeps no permission of its own (a reader who may
see the issue may know which workflow governs it); only the drawing is gated.

**The role selector offers every role the project screen already lists** — answer
**B** to choice 3. "What may a developer actually do here" is precisely the
question of somebody administering the workflow, and the permission that answers
it already exists; the screen is behind it. Default selection is the reader's own
roles as a union, and the selector is omitted entirely when there is only one
thing to pick.

The population is `Services::ProjectOptions.visible_roles` — the roles with
members in the project, plus any role that already holds a scope here, which is
exactly what the settings tab and the matrix use. **Not every role in the
installation:** `docs/DECISIONS.md` settled on 2026-08-26 that the project screen
offers only the roles the project has, and *Non member* and *Anonymous* stay an
administration matter. This selector changes who may be *looked at*, not which
roles the project screen knows about.

### The route

- **`Services::WorkflowGraphQuery`** — for one (project, tracker, role ids): the
  nodes and the edges, each edge carrying its condition (unconditional, author,
  assignee) and which of the selected roles grant it, plus core's
  `old_status_id = 0` *new issue* node as the entry point. Per-role scope state,
  so the three states of INV-3 are reported rather than inferred from the rules.
  Self-transitions excluded as elsewhere. One scope lookup (the Resolver's cached
  point lookup, INV-6), one edge query, one status query.

  **A query object of its own, not a mode on `TransitionMapQuery`.** That class
  reads the tracker, the status and the status list off one issue on purpose —
  its own comment says why, and it has no issue to read here. What the two share
  is the population split: the project's own rows for the roles the project
  answers for, the generic rows for the rest, both relations naming a
  `project_id` explicitly (INV-4). Extract that as a helper returning **the two
  finished relations**, never a base relation carrying only the tracker — the
  distinction the comment above `TransitionMapQuery#population` draws, and the
  reason to extract at all: INV-4's discipline written twice is INV-4's
  discipline with two places to get it wrong.

  Availability — WP8's honesty clause — has no meaning here. There is no issue
  and no reader identity to judge an edge against, so no edge carries it, and the
  drawing says what the workflow permits rather than what one reader may do now.

- **`Services::WorkflowGraphLayout`** — a pure function from nodes and edges to
  coordinates, in four phases: break cycles (depth-first from the entry node,
  recording back edges rather than dropping them); assign layers (longest path
  over the forward edges); order within a layer (median heuristic, four
  alternating sweeps); assign coordinates (even spacing, then a straightening
  pass). Two details that were measured on the model rather than guessed:

  - **Only forward edges may pull during straightening.** A returning arc points
    at a node far to the right; letting it tug drags the main path into a
    staircase. Straightening with every edge made the drawing visibly worse.
  - **An edge spanning more than one layer needs dummy nodes**, so the ordering
    pass keeps room for it. Bowing it over the intervening node is what the model
    does and it is the difference between "usually tidy" and "always tidy".

  Statuses the selected roles cannot reach from the entry node go in a band of
  their own below the drawing, labelled, rather than being given a layer — that
  band *is* the first diagnostic.

  **Determinism is a requirement, not a nicety.** Same input, same output, on
  every Ruby and every database. Every iteration is over an explicitly sorted
  collection; nothing iterates a hash whose order came from a query without an
  `ORDER BY`. This is the shape of failure that otherwise appears as one red cell
  out of nine with a different random seed.

- **Text that does not fit.** SVG does not wrap. A status called *Waiting for the
  customer's answer* does not fit a 130 px node. Wrap in Ruby, on spaces, to at
  most two lines with an em-width estimate; truncate beyond that and carry the
  full name in the node's `<title>`. Node width stays fixed so the layout remains
  a pure function of the graph.

- **The renderer**, a view partial building inline SVG:
  - The `viewBox` comes from the **drawn** extent, not from the node positions.
    The returning arcs bow below the rows; a `viewBox` derived from the nodes
    alone clips them, which is a bug that renders silently. It carries a spec.
  - `currentColor` for the neutral strokes and the text, a literal hue only for
    the marks that carry meaning. Redmine 7.0 ships no dark mode, but third-party
    themes change exactly the colours one would otherwise hard-code.
  - Arrowheads as `<marker>`, one per semantic colour — `context-stroke` is not
    safe on every browser the supported versions run on.
  - Every edge carries a `<title>`: from → to, the condition, the granting roles.
  - `role="img"` and an `aria-label`, and **the table underneath is the readable
    twin, not an afterthought** — no `aria` attribute makes a drawing legible to
    a screen reader, which is the same reason WP8 shipped a table in the first
    place.
  - No `<foreignObject>`, no `<script>` and no `<style>` inside the SVG.

- **The screen.** `GET projects/:project_id/workflow/graph` on
  `ProjectWorkflowsController`, whose `before_action :find_project_by_project_id`
  then `:authorize` already check the permission against the project in the path
  before anything else runs (INV-7). The tracker and the role arrive as parameters
  and are picked out of `ProjectOptions.trackers` and
  `ProjectOptions.visible_roles`, exactly as `#find_tracker_and_role` already
  does, so a parameter can only ever name something the project offers. Reached
  from the settings tab row, from the matrix header beside *Compare with the
  generic workflow*, and from the WP8 panel.

  **The action must be registered in `init.rb` or `authorize` denies it.** Add
  `graph` to the action list of **both** permissions, as `transitions`,
  `permissions` and `compare` already appear in both: `view_project_workflow_rules`
  carries `read: true`, and a member holding only `manage_project_workflow_rules` would
  otherwise get a 403 on a screen they may plainly see. Forgetting this is a
  silent 403 on a route that looks correctly written, so it carries the
  authorization spec below rather than a comment.

- **The link from the WP8 panel** — one line in
  `app/views/project_workflow_maps/_map.html.erb`. Gate it the way
  `ProjectWorkflowMapsHelper#project_workflow_map_edit_link` already gates *Open
  this workflow*: `User.current.allowed_to?(action, project)` against the very
  action the target authorizes, **not** against a permission name — two
  permissions reach these screens, and that helper's comment says why naming one
  of them gets it wrong. A link that answers 403 is worse than no link.

- **Diagnostics**, from the graph already in hand and costing no query:
  unreachable from the entry node, no outgoing edge, and a status the tracker
  uses that no rule for these roles mentions at all.

- **INV-9 is untouched.** Everything here is in the plugin's own views and
  controller; no new Deface anchor. The count stays **fifteen** in `CLAUDE.md`,
  in `docs/design.md` and in the spec's comment — do not bump it.

- Strings in `en` and `nl` by hand, the other six translated (never English text
  in a non-English file); `spec/locales_spec.rb` asserts parity across all eight.
- A README paragraph and a CHANGELOG line **in this package**, as WP8 carried its
  own rather than waiting for a second release pass. The README's is worth
  writing carefully: this is the feature a Jira leaver looks for first, and the
  README is where they look.

### Cost (G6)

Nothing changes for a screen that does not ask for the drawing. Asking for it
costs the three queries above and a layout pass that is quadratic in the number
of nodes per layer, over a graph with as many nodes as the installation has
issue statuses — usually six to fifteen, rarely more than thirty. The answer is
small: the model measures 3.8 kB of markup for seven nodes and fourteen edges, so
twelve statuses and thirty rules land near 8 kB, about 2 kB compressed. **No
caching in this package.** If it is ever wanted the key is (project, tracker,
sorted role ids, the scope row's `updated_on` or `generic`, the rule count) —
named here so it need not be re-derived, and left out because at these amounts it
would be complexity without a reason.

The drawing is inline SVG with the layout computed in Ruby. Recorded because the
question was asked and the answer is not the obvious one: at this size the
drawing technology does not affect speed at all — what matters is what reaches
the browser and when. SVG wins on everything around it: the status names stay
real text (selectable, findable with Ctrl-F, readable aloud), `currentColor`
carries the theme, and it prints. Canvas loses all of that and only starts to win
back above thousands of elements. Mermaid is about a megabyte, Graphviz as
WebAssembly two to three, and dagre / ELK / Cytoscape want an npm build step this
plugin does not have.

### Tests

- **Layout, as a pure function:** a known graph gives known layers; a cycle
  terminates; an unreachable status lands in the band below; the same input twice
  gives byte-identical output.
- **The clipping regression:** the rendered `viewBox` contains every drawn path.
  It fails on the naive implementation that sizes from the node positions.
- **Query:** a project with its own workflow draws its own edges and never the
  generic ones, and an inheriting one the reverse (INV-1, INV-4); the per-role
  states of INV-3; a subproject does not inherit its parent's (INV-6).
- **Authorization:** every entry point answers 403 without
  `view_project_workflow_rules`; a member holding **only** `manage_project_workflow_rules`
  reaches it (the registration trap above); and a `project_id` among the
  parameters cannot widen the project named by the path (INV-7). A role the
  project does not offer, and a tracker it has not enabled, answer 404 rather
  than drawing anything.
- **The three states drawn:** an own empty workflow draws the entry node and
  nothing else with the sentence that says that is deliberate, rather than a
  blank frame.

Out of scope: editing the workflow inside the diagram (that is Jira's workflow
editor, a far larger thing, and Redmine's tick-box matrix is honestly better at
it); the drawing in the issue panel (choice 1, answer A); exporting it as a file;
and the bulk-edit form, for the reason WP8 already gives.

**Done when** a reader with `view_project_workflow_rules` can open a project's workflow
as a drawing for any tracker and any role in that project, an inheriting
combination draws the generic workflow and says so, an own empty one draws the
entry node alone with its explanation, the diagnostics name the unreachable and
dead-end statuses, the `viewBox` contains every drawn path, two runs of the same
input produce identical output, and the specs are green on all nine CI cells.

---

---

# The hardening track — WP10..WP16

WP0..WP9 built the plugin. This track makes it something that can be given to
somebody else and still be there in three Redmine generations. It exists because
three reviews landed on 2026-08-28 — a whole-stack compatibility run against all
forty-four of Jan's other plugins, a production-readiness audit, and a ChatGPT
review Jan commissioned in parallel — and between them they said one thing three
ways: the plugin is correct, and its *surface* is larger than it needs to be.

Two ADRs carry the architecture: **ADR-002** (compatibility is an object) and
**ADR-003** (the project dimension moves to screens the plugin owns). Everything
below implements one of them or clears a confirmed finding.

Nothing here is user-visible except WP10's permission rename and WP12's second
administration entry point. The rest is the plugin doing the same thing with less
of Redmine held in its hands.

---

## WP10 — Ecosystem safety

**Why first.** One of these is a blocker on Jan's own stack today: with
`redmine_custom_workflows` installed — which he runs — **nobody, not even an
administrator, can save a project workflow.** Everything else in this track is
worth nothing until that is true again.

- **The permission name collision** (`2026-08-28-claude-plugin-compat-5.1.md` F01,
  blocker). `Redmine::AccessControl` keeps a flat array and
  `AccessControl.permission(name)` returns the **first** match; plugins load in
  alphabetical directory order, and `redmine_custom_workflows` sorts first with an
  empty registration of the same name. Rename the pair, symmetrically —
  `view_project_workflow_rules` / `manage_project_workflow_rules` (F10 of that run
  is Jan's choice between renaming one or both; renaming both is the
  recommendation, because an asymmetric pair on the role form reads as a
  distinction rather than as a scar). A migration renames the permission inside
  the serialized `roles.permissions` array, and it is reversible.
- **The general lesson, made permanent.** Permission names are a global namespace
  and this plugin had the only unprefixed globals in the repository — routes,
  helper methods, CSS classes, JavaScript globals and locale keys are all already
  prefixed. A convention spec pins that: everything the plugin registers into a
  shared namespace carries its prefix.
- **The version probe** (same run, F02, major). `project_workflows_svg_icons?`
  asks `respond_to?(:sprite_icon)`, and two neighbours define that method on
  Redmine 5.1, so the plugin takes the Redmine 6 branch on a 5.1 host and the
  "no rules here" marker vanishes from the workflow summary. Replace it with a
  version comparison. ADR-002 says where that lives, but the fix does not wait
  for WP11 — an interim constant is fine and WP11 moves it.
- **Four confirmed defects from the audit**, each small and each with a test that
  is red on the old code: `WorkflowsHelper` off the core helper and onto the
  controller chain (F01 — a stopgap that WP12 deletes, worth having because WP12
  is weeks away); the three `TIMESTAMP 'literal'` sites made portable (F02);
  `is_a?(Hash)` in both writers (F04); and a graph request naming one valid and
  one invalid role answering 404 as its own comment promises (F05).

**Done when:** the plugin's write actions work on a host with
`redmine_custom_workflows` installed, the summary page draws 5.1's own empty
marker on 5.1 with the RedmineUP shims present, the suite is green on SQLite as
well as on the nine cells, and `spec/plugin_conventions_spec.rb` fails if a new
unprefixed global is registered.

**Done**, in two commits. `580a8d3` answered the whole-stack run: both
permissions renamed with a migration that refuses to guess where a neighbour may
own the legacy grant, the version probe replaced by
`Redmine::VERSION::MAJOR`, and the permission-ownership convention example added.
The four defects of `2026-08-28-claude-audit` followed: `WorkflowsHelperPatch`
onto the two controllers' helper chains, the three `TIMESTAMP '...'` literals
made portable, `is_a?(Hash)` in both writers, and a graph request naming one
offered role and one that names nothing answering 404. Two things came out of it
that were not in the plan: `CoreMethodDigest` had to learn both attachment
styles, or three digests would have vanished from the gate the moment the patch
stopped being a prepend; and the graph selection moved into
`RedmineProjectWorkflows::GraphSelection`, because the addition took
Metrics/ClassLength past its limit and this repository extracts rather than
raises it.

### Progress, 2026-08-28

**Done, and verified on a 45-plugin Redmine 5.1 host:**

- **The permission rename.** `view_project_workflow_rules` /
  `manage_project_workflow_rules`, answered **B** by Jan. Migration 006 carries
  existing grants across and is reversible; where another plugin still registers
  the legacy name the stored symbol is ambiguous, so it leaves that grant alone
  and prints what to grant instead rather than renaming a neighbour's permission
  away or widening what a role may do. On the real host the request that
  answered 403 answers 302 and writes its rows; the role form has no duplicate
  checkbox ids.
- **The version probe.** `VersionHelper.core_sprite_icons?` is
  `Redmine::VERSION::MAJOR >= 6` — the interim constant this work package calls
  for, and the single place **WP11 has to move into ADR-002's manifest**. The
  two spec files that restated `respond_to?(:sprite_icon)` now call that
  predicate. `/workflows` draws 5.1's `icon-not-ok` again with the RedmineUP
  shims present.

Suite: **873 examples, 0 failures** on 5.1, 6.1 and 7.0 with PostgreSQL, and on
the 45-plugin 5.1 host, which had 69 failures before.

**Not started:** the unprefixed-globals convention spec — what exists is
narrower, asserting only that the registration `AccessControl.permission(name)`
answers with is this plugin's — and the four confirmed defects of
`2026-08-28-claude-audit.md` (F01, F02, F04, F05). The suite has **not** been
run on SQLite since, so that half of *done when* is unproven.

---

## WP11 — Compatibility as an object

Implements **ADR-002**. Read it first; this is the build order.

- **The manifest.** `lib/redmine_project_workflows/compatibility.rb` plus its
  data: verified Redmine minors, Ruby and Rails ranges, databases, per-minor core
  method digests, declared private-API dependencies. `core_method_digests.yml`
  becomes part of it rather than a file beside it.
- **Every version fact reads the manifest.** `VersionHelper` first — WP10's
  interim constant moves here — then the drift spec, the conventions spec, and
  the generated Compatibility section of the README.
- **Three states at runtime.** *verified* (silent, no digest work), *unverified
  with no drift* (a log line and a diagnostics entry), *unverified with drift* (an
  administrator-visible warning naming the changed methods and where core defines
  them). Digests are computed lazily and only in the second and third case; they
  cost 34.5 ms for nineteen methods, measured on a 5.1 host outside RSpec.
- **The gate covers what it depends on.** `CoreMethodDigest::TARGETS` extends to
  singleton classes, which brings in `WorkflowRule.copy_one` and — the two that
  matter — `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions`, the methods INV-1's routing rests on.
  `Issue#roles_for_workflow` gets a declared-dependency entry of its own, because
  it is called rather than shadowed and has no `super_method` to digest.
- **A diagnostics page**, administrator-only: compatibility state, the digest
  report, the registered Deface overrides, the patch ancestry of every class the
  plugin prepends, and — the generalisation of WP10's blocker — a check that every
  permission the plugin registered still resolves to *its own* action list.
- **CI fails where runtime warns.** An unknown minor under test is a failed
  compatibility job, not a skip.

**Done when:** a host running an unlisted Redmine minor reports one of the three
states correctly for both a drifted and an undrifted core, the diagnostics page
names a captured permission, and the compatibility job fails on a minor with no
manifest entry.

**Done**, 2026-08-28, in two commits.

The manifest is `lib/redmine_project_workflows/compatibility.yml` and
`RedmineProjectWorkflows::Compatibility`; `spec/upstream/core_method_digests.yml`
is absorbed into it. `VersionHelper` reads it, the drift spec reads it, the
README's Compatibility section is compared against it by four examples, and
`spec/plugin_conventions_spec.rb` fails if anything in `app/` or `lib/` reads
`Redmine::VERSION` anywhere else. The three states resolve lazily and are
announced once per process from `init.rb`; the drift spec **fails** on an
unmeasured minor where it used to skip. `CoreMethodDigest::TARGETS` covers the
singleton classes and the manifest's declared dependencies, so nineteen watched
methods became twenty-three — and the first thing that found was that 7.0
rewrote `WorkflowTransition.replace_transitions` (an index in front of the same
rules; the plugin replaces the method outright, so nothing followed).

`Administration → Project workflow diagnostics` is the page: the compatibility
state and the drift table, the permission-ownership check that generalises
WP10's blocker, the attachment of every patch, and the registered Deface
overrides as a listing. Two things came out of building it that were not in the
plan: `IssuesControllerPatch` attaches `ProjectWorkflowMapsHelper` rather than
itself, so the attachment table needed a fourth element and reported a correctly
applied patch as missing until it had one; and the singleton-coverage example
asked the manifest where it meant to ask the measurement, and was green with the
new targets reverted.

Not done, and deliberately: **a CI job of its own**. The compatibility question
is asked inside the rspec job on every one of the nine cells, which is where the
host is, so a separate job would either duplicate the matrix or ask the question
somewhere it cannot be answered.

---

## WP12 — Owned administration screens

Implements **ADR-003**, and it is the large one. Build order matters because the
branch stays green at every commit:

1. **Done.** The `admin_menu` entry, routes and controllers for the plugin's own
   administration area, rendering core's `workflows/_form` exactly as
   `ProjectWorkflowsController` already does. `ProjectWorkflowRulesController`,
   under `/project_workflow_rules`.
2. **Done.** The scope panel, the project selector, the summary and the inventory
   link are on it, with a spec of their own.
3. **Done.** The copy screen is on it, with its six selectors and their
   validation.

   Steps 1-3 were **additive**: core's screens still carried the eleven overrides
   and the 468-line patch, and their spec was untouched and green. Steps 4-8 are
   what take them away, and the behavioural spec moves with them.
4. **Done.** `WorkflowsControllerPatch` is cut back to the `project_id: nil`
   predicate — 468 lines to about 40 of code, on `index`, `edit`, `permissions`
   and `find_statuses`. Not on `update` and `update_permissions`, which the plan
   and ADR-003 both named: their writes already go through
   `WorkflowTransition.replace_transitions` and
   `WorkflowPermission.replace_permissions`, which the plugin's own singleton
   patches route to the writers with `project_id` fixed at `nil` (INV-1). What
   both lists missed is `find_statuses`, whose "used statuses only" query is a
   `workflows` query like any other.
5. **Done.** `WorkflowsHelperPatch` is deleted, and WP10's stopgap with it. What
   replaces it is `WorkflowsControllerHelperPatch`, which attaches
   `ProjectWorkflowMatrixHelper` to core's controller and nothing of its own:
   core's `workflows/_form` carries the row and column actions of WP5, so without
   it core's own workflow screen raises `NoMethodError`.
6. **Done.** Ten overrides in nine files, and their assertions, are **deleted,
   not rewritten**; the eleventh is narrowed to the cross-link. INV-9 is **five
   in three files**, changed in `CLAUDE.md`, `docs/design.md` and
   `spec/integration/deface_overrides_spec.rb`.
7. **Done.** Cross-links both ways between core's workflow screen and the
   plugin's.
8. **Done.** The runtime anchor check is on the diagnostics page: for each of
   the five overrides, whether its selector still finds its anchor in the
   template this host ships. Three answers — found, not found, could not be
   checked — and only the middle one counts against the page's overall verdict.

**Done when:** the table in ADR-003 is true — overrides 15 → 5, the controller
patch under 60 lines, shadowed core methods down by the two the deleted modules
carried, core helper prepends 0 — and nothing a user can do on the administration
screens has changed.

---

## WP13 — One write-coordination service, and bounded bulk writes

Two findings, one mechanism.

- **Concurrency** (audit F07). **Done, 2026-08-29.** Project writes lock their
  scope rows; a generic write had no scope row and took nothing, so two
  administrators could leave duplicate rows. The calibration matters and is in
  the finding: **core has the identical race and the plugin inherited it** —
  core's own `replace_transitions` reads outside a lock and carries an
  opportunistic duplicate-repair line to prove it knows. The plugin is the write
  path for both populations and fixed it once. `Services::WriteCoordinator` is
  the one entry point and a caller names one key,
  `(rule_type, project-or-generic, tracker, role)`; a project's scope row is its
  coordination row, and the generic population gets a row on a plugin-owned table
  (`project_workflow_write_locks`, migration 007) rather than advisory locks,
  which have no portable equivalent across PostgreSQL, MySQL and MariaDB. Taken
  in a fixed order by every write path: both rule writers, the three scope
  actions, and **both** copy screens — Redmine's own reaches the generic write
  through `WorkflowRule.copy_one`, which is why the lock is taken in the model
  beside the write. The spec that pinned the asymmetry is inverted and says so.
  See `docs/DECISIONS.md`, 2026-08-29, and the Resolution under F07.
- **Bulk writes** (audit F08). **Done, 2026-08-29.** Measured: 5 projects × 3
  trackers × 3 roles × 36 cells is 1,620 rows and 48 statements — the statement
  count is constant per project, the row count is not. An "all projects"
  selection on a large installation extrapolates to millions of rows in one
  transaction holding coordination rows throughout. The transaction stays and the
  selection is bounded: `Services::WriteBudget` projects the row count exactly
  before anything is written, the Save button asks above
  `bulk_confirm_threshold` (the setting that already existed) and the save is
  refused above `bulk_write_ceiling` (new, 200,000, `0` means no ceiling). **No
  background job:** Redmine 5.1's default ActiveJob backend is the async adapter,
  which is not something a workflow write may depend on.
- **The inventory's filters** stop materialising every project (audit F09), and
  archived projects leave the selector.

**Done when:** a real two-connection test on all three databases shows no
duplicate logical key from concurrent generic saves, and a whole-installation
save is either confirmed, batched or refused before any row changes.

---

## WP14 — The remaining defect backlog

- Deleting an issue status that empties a project scope (audit F03) — warn rather
  than clean up, so that two of INV-3's three meanings are not collapsed on the
  administrator's behalf.
- `deface` gets a lower bound and a next-major upper bound (audit F10). ADR-003
  reduces the exposure from the other side.
- The `ScopeCopier` / `ProjectWorkflowCopier` asymmetry is settled — narrowed, or
  recorded in `docs/DECISIONS.md` as deliberate (audit F11).
- The copy form's item count is narrowed to the source's enabled trackers.
- The graph becomes a **switchable feature with a size ceiling**. Not because it
  is defective — it is pure functions with 800 lines of specs — but because a
  feature that can be turned off is a feature that does not have to be defended
  on every upgrade.

---

## WP15 — The test debt three reviews named

In priority order, because this is the package most likely to be cut short:

1. **Neighbour coexistence.** A synthetic neighbouring plugin that alias-chains
   and prepends the same methods, loaded before *and* after this one. The
   whole-stack run proved this matters with real plugins; a spec makes it a gate
   rather than an annual exercise.
2. **The full role matrix per action** — anonymous, non-member, member with
   neither permission, view-only, manage, administrator — and cross-project
   substitution: authorized on A, path project B, tracker and role from A.
3. **Stored XSS through status names** in the SVG, the table, the tooltip and the
   JavaScript response.
4. **`each_batch_predicate` at exactly `DELETE_BATCH_SIZE`** on all nine cells.
   PostgreSQL was measured safe to 1,000 nested `OR`s during the audit and SQLite
   fails well under 100; MySQL and MariaDB are unmeasured, and nothing in the
   suite reaches more than a handful of terms.
5. **Upgrade rehearsals** from 0.0.3 and from each later release, with populated
   data: project rules, own-empty scopes, duplicates, orphaned audit users.
6. **Scale**: a 10,000-project inventory, and the issue-save hot path's query
   count for a user holding many roles.

---

## WP16 — Release engineering

- An upgrade rehearsal from the previous release, scripted and repeatable.
- A **downgrade** procedure, which does not exist today at all.
- A scripted, backup-aware uninstall.
- Release criteria written down, and the alpha warning removed only when they
  pass.

---

## Sequencing

WP0 is independent. WP1 gates everything after it. WP3 needs WP1's scopes to
report anything true; WP4 needs WP1 and reuses WP3's state labels. WP5 touches
different files from WP4 and can run alongside it. WP6 needs WP1 (audit
columns) and WP3 (where the compare view is reached from). WP8 needs WP1 (it
resolves a scope like everything else) and nothing later. WP9 needs WP1 for the
same reason and WP4 for the screen it attaches to, and it reuses WP8's population
split; it changes nothing WP8 renders, so the two cannot conflict. **Jan chose WP7 first
and then WP8**, in a session of its own, so the release pass covers what exists
at that point and WP8 carries its own README paragraph, CHANGELOG line and
locale keys rather than waiting for a second release pass.

**The hardening track.** WP10 is independent and comes first, because its
blocker makes the plugin unusable on Jan's own stack. WP11 comes next because
WP12 and WP16 both read the manifest it builds, and because WP10 leaves an
interim version constant for it to absorb. **WP12 before WP13**, deliberately:
WP13's lock service touches the four write paths, and WP12 rewrites where two of
them live — the other order does the work twice. WP14 and WP15 can run alongside
each other and after WP12. WP16 is last by definition.

## Definition of done

`spec/characterization/` is empty, the nine-cell CI matrix is green, a project
administrator can give their project its own workflow and see at a glance which
projects deviate, and the README describes what the plugin actually does.

**For the hardening track (WP10..WP16), and therefore for a release:** the
plugin's write actions work on a host carrying every other plugin Jan runs; a
Redmine minor nobody has tested reports whether anything the plugin copied has
changed; the Deface surface is two anchors; generic and project writes have one
concurrency policy; a whole-installation write is bounded before it starts; and
the alpha warning is gone because the release criteria in WP16 passed, not
because somebody decided it looked ready.
