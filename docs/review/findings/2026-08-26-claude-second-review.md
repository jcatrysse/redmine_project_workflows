# Review — 2026-08-26, Claude (second run)

- **Reviewed:** `claude/dev` at `9a1a9ef`
- **Suite run:** yes — 585 examples, 0 failures on **Redmine 5.1 + PostgreSQL 16**,
  **6.1 + PostgreSQL 16**, **7.0 + PostgreSQL 16** and **7.0 + MariaDB 10.11**.
  Migration reversibility (up → 0 → up) run before each suite on all four hosts,
  and the schema checked by hand afterwards: no `workflows.project_id`, no
  `project_workflow_scopes`. RuboCop clean (91 files). `dev/check-bulk-js.mjs`
  green. `zeitwerk:check` passes.
- **Not run:** 5.1 and 6.1 against MySQL and MariaDB — five of the nine CI cells
  were not reproduced here. Core's source for all three supported versions was
  checked out and read rather than recalled.
- **Caveat on the review itself:** done in one context, not a fresh subagent, so
  it is self-review in the sense `CLAUDE.md` warns about. Every claim below was
  therefore checked against a running host rather than argued.

## Summary

Thirteen findings. Two are major and both sit on one path — *an administrator
presses Save on an administration matrix* — which is the part of the plugin that
diverges most from core and carries the least test coverage. One of them changes
what stock Redmine does, because the plugin routes core's own write method
through the same writer.

The scope model itself holds up. INV-1 is closed with tests, the resolver is a
point lookup as designed, the version-conditional code is where it says it is,
and the places where the plugin reimplements core were checked word for word
against 5.1, 6.1 and 7.0 and match. Nothing was found in authorization: every
action authorizes against the project in its own path, every parameter that
reaches a query is shape-checked or intersected with a server-built list, and the
raw SQL only ever interpolates `Integer()`-coerced ids.

| | Finding | Severity | Status |
| --- | --- | --- | --- |
| R01 | A cell left at *(No change)* is deleted anyway | major | fixed |
| R02 | Saving the administration matrix gives an inheriting project an own **empty** workflow | major | fixed |
| R03 | `issue_statuses/index` reads `workflows` with no `project_id`, and is not in the design's "complete list" | minor | fixed (documented) |
| R04 | An administration save is one round trip per combination | minor | fixed |
| R05 | Every project is materialised into the project selector | minor | wont-fix |
| R06 | `Issue#workflow_rule_by_attribute` becomes public | minor | fixed |
| R07 | The helper injected into `issues/_attributes` can raise for a neighbour | minor | fixed |
| R08 | A malformed matrix submission is a 500 on the administration screens | minor | fixed |
| R09 | `ProjectWorkflowScopesController` has no `layout 'admin'` | minor | invalid |
| R10 | `design.md` says "ten anchors" under a table of fifteen overrides | minor | fixed |
| R11 | `locales_spec` compares only top-level keys; three locales use two words for one thing | minor | fixed |
| R12 | The threshold setting accepts anything and silently falls back | minor | fixed |
| R13 | A matrix save is one transaction per project, not one per save | minor | fixed |

---

### R01 — A cell left at *(No change)* is deleted anyway

- **Status:** fixed
- **Severity:** major — silent loss of workflow configuration, including the
  generic workflow
- **Where:** `lib/redmine_project_workflows/services/transition_writer.rb`,
  `delete_transitions_for_scope`

One cell of the transitions matrix is **three controls** — `always`, `author`,
`assignee`, one per grid — over **two stored rows**: the unconditional row, and
the row carrying whichever of the two flags apply. Each of the three can
independently render as a `<select>` whose default is core's *(No change)*, and
the controller strips that value before the writer sees it.

The delete was keyed on `(old_status_id, new_status_id)` alone. So any surviving
column put the whole cell into the delete list, and the delete removed **every**
row for that cell — in every workflow of the selection.

Reachable from the default state of the screen. With two projects selected where
one permits a transition and the other does not, the `always` cell renders as a
mixed dropdown while the `author` and `assignee` cells render as unchecked
checkboxes with their paired hidden `0`. Pressing Save without touching anything
submits `{'author' => '0', 'assignee' => '0'}` for that cell, and the transition
is gone.

Measured on Redmine 7.0 + PostgreSQL, through the real controller action:

```
always cell is a mixed select: true
flash: "Successful update."
A's rules after Save: 0 (expected 1)
```

And at the model API, against core's own implementation reached through
`Method#super_method`:

```
plugin  BEFORE [[1, 1, 2, false, false]]   AFTER []
core    BEFORE [[1, 1, 2, false, false]]   AFTER [[1, 1, 2, false, false]]
```

Because the plugin routes `WorkflowTransition.replace_transitions` through this
writer (INV-1), the same happens on the **generic** workflow — so this was a
change to what stock Redmine does, not only to the plugin's own path. It also
contradicts the README (*"Every cell you leave alone stays alone"*) and the
sentence the matrix itself prints above the grid.

The mirror case loses the other row: with `always` submitted as `1` and the
`author` column left at *(No change)*, the stored author row is deleted.

`spec/services/transition_writer_spec.rb:150` covered only the cell where *all
three* columns say no change, which arrives as an empty rule hash. The partial
case — the one the screen actually produces — was untested.

- **Resolution:** the delete is now per rule group: the unconditional row is
  deleted only for cells whose `always` column was submitted, the shared
  author/assignee row only for cells whose `author` or `assignee` column was.
  The shared row is read before the delete and re-inserted carrying whichever of
  its two flags was left at *(No change)*, which is what core's row-by-row update
  does. Six examples in `transition_writer_spec.rb` and two in
  `workflows_controller_spec.rb`; six of the eight are red on the old code (the
  other two are positive controls that must pass on both sides).

### R02 — Saving the administration matrix gives an inheriting project an own empty workflow

- **Status:** fixed
- **Severity:** major — a project can stop permitting any status change at all,
  from one Save, with a success message
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_patch.rb#update`
  → `TransitionWriter` → `ScopeWriter.ensure_scopes`

`ProjectWorkflowsController#refuse_write_while_inheriting?` has refused this
since WP4, and `docs/design.md` states the rule: *"accepting it would turn 'save'
into 'enable', and the three actions of INV-3 stay the only way to take a
workflow over."* The administration screens did not implement it.

Two halves, and the second is what makes the first dangerous:

1. The grid shows the rules the selection holds **itself**, so a project that
   inherits renders **empty** — every checkbox unchecked. Measured:

   ```
   the s1 -> s2 always cell, project selected (project inherits):
     <input type="checkbox" name="transitions[1][2][always]" …>
   the same cell, generic selected:
     <input type="checkbox" name="transitions[1][2][always]" … checked="checked">
   ```

   The panel above says *Inherits the generic workflow*, but the grid below it
   says the opposite, in the language the screen is read in.

2. Pressing Save — with nothing touched — wrote that emptiness back:

   ```
   scopes after a plain Save: [[1, 1, 1, "transitions"]]
   project rules: 0     generic rules: 1
   flash: "Successful update."
   ```

   Which is an own **empty** workflow: no issue in that project can change status
   for that role. ADR-001 names exactly this state as the one to keep unreachable
   by accident, and it is why *give own workflow* preselects the copy.

Selecting **All** in the project selector applies it to every project on the
installation at once.

- **Resolution:** the writers now write only into (tracker, role) combinations
  the project has already taken over, and return how many they refused;
  `ScopeWriter.ensure_scopes` is removed, so creating a scope is `.enable` and
  nothing else. The controller reports the refusal as a warning and withholds the
  success notice when nothing was written. The scope panel says, before anything
  is pressed, how many combinations of the selection inherit, that those are the
  empty-looking ones, and that Save will not change them. `docs/design.md` and
  the README are amended, because this changes what an administrator sees.
  Eight examples across `transition_writer_spec.rb`, `permission_writer_spec.rb`,
  `workflows_controller_spec.rb` and `deface_overrides_spec.rb`; all eight red on
  the old code.
- **Note on the specs that changed:** nineteen existing examples arranged project
  rules by calling a writer and relying on it to create the scope. That
  arrangement was relying on the defect, so they now give the project its own
  workflow first. Four examples asserted the old behaviour directly (*"creates
  one for each tracker and role it wrote"* and the `.ensure_scopes` block); those
  are inverted or moved onto `.enable`, and the inversion is the point rather
  than a weakening.

### R03 — `issue_statuses/index` reads `workflows` with no project predicate

- **Status:** fixed (documented; no code change)
- **Severity:** minor

`app/views/issue_statuses/index.html.erb:29`, byte-identical on 5.1, 6.1 and 7.0:

```erb
<% unless WorkflowTransition.where('old_status_id = ? OR new_status_id = ?', status.id, status.id).exists? %>
```

It is not in `docs/design.md`'s integration table, which claims to be *"the
complete list: every place in Redmine 5.1, 6.1 and 7.0 that names `WorkflowRule`,
`WorkflowTransition` or `WorkflowPermission`"*. With the plugin installed, the
*not used by any workflow* badge is computed across the generic rules and every
project's.

That is the better answer for a status some project's own workflow uses, and the
wrong one for a project row with no scope — which applies to nothing (INV-3).

- **Resolution:** documented in the integration table rather than changed. It is
  a badge, not a gate: the Delete link beside it is rendered unconditionally, so
  nothing is blocked. Correcting it would need a sixteenth Deface override — one
  more anchor to go stale (INV-9) — for a hint. The same row now also records
  that deleting an issue status can leave a project with a scope and no rules,
  which is an own *empty* workflow, and that nothing warns.

### R04 — An administration save is one round trip per combination

- **Status:** fixed
- **Severity:** minor

`ScopeWriter.create_scopes` made one `create!` per (project, tracker, role).
*Give own workflow* with **All** projects, all trackers and all roles selected is
their product — tens of thousands of statements in a single request.

- **Resolution:** batched with `insert_all` (`INSERT_BATCH_SIZE`, 1000). Every
  value is an id this class resolved from the database or a rule type checked
  against `RULE_TYPES`, which is the same argument `ScopeCopier` already makes
  for its raw `INSERT ... SELECT`; the uniqueness the model would have checked is
  the table's own index. A guard raises on an unknown rule type, which is the one
  thing `validates_inclusion_of` was doing here. `WorkflowRule.copy_generic_to_project`
  is still one statement per combination and is recorded in `design.md` as an
  accepted cost — the set-based form needs a literal tuple list, spelled three
  different ways across the supported databases.

### R05 — Every project is materialised into the project selector

- **Status:** wont-fix
- **Severity:** minor

`Project.sorted` is loaded in full — archived projects included — and rendered as
`<option>` elements on the summary page, both matrices, the copy screen and the
inventory's filters. Core's workflow screens have no such control, so the cost is
the plugin's.

- **Resolution:** recorded in `docs/design.md` under what the screens cost, and
  left. It is the administration section; the list is the same one Redmine
  renders on its own project pages; and narrowing it would mean deciding which
  projects an administrator may not configure. Worth revisiting if somebody runs
  this on an installation with thousands of projects — that is a measurement, not
  a guess, and nobody has made it.

### R06 — `Issue#workflow_rule_by_attribute` becomes public

- **Status:** fixed
- **Severity:** minor

Core declares `private :workflow_rule_by_attribute` immediately after defining
it. The plugin's prepended patch reimplements the method above its own `private`
keyword, so on every host with the plugin installed the method is public — core's
API, quietly widened.

- **Resolution:** `private :workflow_rule_by_attribute` restored in the patch,
  with a structural example in `plugin_conventions_spec.rb` that also holds the
  other two reimplemented methods to core's (public) visibility. Red on the old
  code.

### R07 — The helper injected into `issues/_attributes` can raise for a neighbour

- **Status:** fixed
- **Severity:** minor

The Deface override injects `project_workflow_map_link(@issue)` into a partial
**core** owns. `Patches::IssuesControllerPatch` puts the helper into
`IssuesController`'s chain, and core renders `issues/_attributes` from
`issues/_form` only — but a neighbouring plugin that renders `issues/_form` from
a controller of its own reaches the expression with no such helper and raises
`NoMethodError` on its own screen.

- **Resolution:** guarded with `respond_to?`. Structural example in
  `plugin_conventions_spec.rb`, because the negative case needs a controller this
  suite does not have. Red on the old code.

### R08 — A malformed matrix submission is a 500 on the administration screens

- **Status:** fixed
- **Severity:** minor

`#update` and `#update_permissions` copy core's unguarded
`transitions.each_value { … }`, so `transitions[1]=x` arrives as a String and
raises `NoMethodError`. `ProjectWorkflowsController` has guarded its copy of the
same parameters since WP4. Administrator-only, and core behaves the same way, so
this is an alignment rather than a regression.

- **Resolution:** one guarded helper strips *(No change)* for both matrices at
  whatever depth their leaves are. Two examples, both red on the old code.

### R09 — `ProjectWorkflowScopesController` has no `layout 'admin'`

- **Status:** invalid
- **Severity:** —

The claim was that its `render_404` comes back outside the administration
layout. It does not depend on the controller's layout at all:
`ApplicationController#render_error` renders with `:layout => use_layout`, and
`use_layout` is `request.xhr? ? false : 'base'` on 5.1, 6.1 and 7.0 alike. The
controller has no rendered view of its own, so `layout 'admin'` would change
nothing. Withdrawn.

### R10 — `design.md` says "ten anchors" under a table of fifteen overrides

- **Status:** fixed
- **Severity:** minor

INV-9 asks that the override count be kept in `CLAUDE.md`, `docs/design.md` and
the spec's comment. All three say fifteen. The prose under the table then says
*"All ten anchors exist verbatim…"* — true of the distinct anchors on the
administration screens alone, and misleading directly under a fifteen-row table.

- **Resolution:** the sentence now gives both numbers and says which is which:
  fifteen overrides on twelve distinct anchors, ten of them on the administration
  screens and two on the issue form.

### R11 — `locales_spec` compares only top-level keys, and three locales use two words for one thing

- **Status:** fixed
- **Severity:** minor

Two things:

1. The parity check compares the top-level key lists. A pluralised key whose
   value is a hash missing the form Redmine asks for passes — and that is an
   `I18n::InvalidPluralizationData` at render time, not a fallback.
2. `es`, `pt` and `pl` each used more than one word for *tracker*, and two of
   them for *role*. `pl` still had the English word **tracker** in one string,
   which `CLAUDE.md` forbids outright. Checked against Redmine's own locale
   files: es *Tipo* / *Perfil*, pt *Tipo* / *Função*, pl *Typ zagadnienia*.

- **Resolution:** the spec now asserts that every key pluralised in English is a
  hash carrying `one` and `other` in every locale; the three files use Redmine's
  own words throughout. The spec example passes on the old code too — it is a
  guard against the next locale, not a fix for this one — and the terminology is
  verifiable against core rather than a matter of taste.

### R12 — The threshold setting accepts anything and silently falls back

- **Status:** fixed
- **Severity:** minor

`bulk_confirm_threshold` was a plain text field. Redmine's plugin settings have
no validation hook — `SettingsController#plugin` assigns the submitted hash as it
arrives — so `abc` is stored, and `BulkActionsHelper` then falls back to 50 with
nothing said.

- **Resolution:** `type=number min=0 step=1`, so the field refuses it. The
  fallback stays, because it is what answers for a value saved before the
  attribute existed. Two examples; the field one is red on the old code.

### R13 — A matrix save is one transaction per project

- **Status:** fixed
- **Severity:** minor

`#update` looped over the selected projects, each writer call opening its own
transaction, so a failure part way through left some of the selection rewritten
and the rest untouched. `#duplicate` already wrapped its loop.

- **Resolution:** one `ActiveRecord::Base.transaction` around the loop, for both
  matrices. One example, red on the old code.
