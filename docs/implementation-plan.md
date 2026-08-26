# Implementation plan — WP0..WP8

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
| WP8 | Status help and the transition map on the issue form | not started |

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

- Permissions `view_project_workflow` and `manage_project_workflow` under the
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
the possible status changes.* `design.md` carries the target; this is the route.

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
and the specs above are green on all nine CI cells.

---

## Sequencing

WP0 is independent. WP1 gates everything after it. WP3 needs WP1's scopes to
report anything true; WP4 needs WP1 and reuses WP3's state labels. WP5 touches
different files from WP4 and can run alongside it. WP6 needs WP1 (audit
columns) and WP3 (where the compare view is reached from). WP8 needs WP1 (it
resolves a scope like everything else) and nothing later. **Jan chose WP7 first
and then WP8**, in a session of its own, so the release pass covers what exists
at that point and WP8 carries its own README paragraph, CHANGELOG line and
locale keys rather than waiting for a second release pass.

## Definition of done

`spec/characterization/` is empty, the nine-cell CI matrix is green, a project
administrator can give their project its own workflow and see at a glance which
projects deviate, and the README describes what the plugin actually does.
