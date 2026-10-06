# ADR-003 — The project dimension moves to screens the plugin owns

- **Status:** accepted, 2026-08-28 (Jan asked for the architectural work to be
  done now, before any rollout)
- **Supersedes:** nothing formally. It changes how WP1–WP6 delivered the
  administration side, not what they deliver.

## Context

Today the project dimension is bolted onto Redmine's own administration screens.
That costs two things, and both of them are paid on every Redmine upgrade:

- **Eleven of the fifteen Deface overrides** hang on markup in
  `workflows/edit`, `workflows/permissions`, `workflows/index`,
  `workflows/copy` and `workflows/_action_menu` — views the plugin does not own.
  INV-9 exists because an unmatched anchor is silent, and
  `spec/integration/deface_overrides_spec.rb` is an unusually good control. It is
  still a control over a hazard that does not have to exist.
- **`WorkflowsControllerPatch` is 468 lines** replacing six core actions. Only a
  fraction of that is the thing core actually gets wrong; the rest is project
  selection, scope panels, bulk reporting and copy validation — plugin behaviour
  living inside a core controller.

Two reviews on 2026-08-28 arrived at "reduce the core-modification surface" from
opposite directions, and one of them proposed exactly this. Neither costed it,
and the cost is much lower than it looks, for a reason already proven inside this
repository: **`ProjectWorkflowsController` renders core's `workflows/_form`
partial today.** Reusing core's grid from a screen the plugin owns is not a
hypothesis here; it has been shipping since WP4.

A third fact settles the entry point. `Redmine::MenuManager.map :admin_menu` is a
real, stable extension point — verified in 7.0-stable — so an administration
screen of the plugin's own needs **no override at all** to be reachable.

## Decision

**Redmine's workflow administration screens keep doing exactly what core does,
correctly scoped to the generic workflow. Everything about projects moves to
screens the plugin owns.**

Concretely:

1. A new administration area under the plugin's own routes and controllers,
   reached from an `admin_menu` entry: the project matrices, the scope panel,
   the project selector, the summary, the inventory and the copy screen.
2. Those screens go on rendering core's `workflows/_form` partial, as the
   project settings screens already do. Core's grid stays core's grid.
3. `WorkflowsControllerPatch` shrinks to what core genuinely gets wrong, which
   is one thing: its queries carry no `project_id`, so they read project rows as
   generic (INV-4). What remains is a `project_id: nil` predicate on `index`,
   `edit`, `permissions`, `update` and `update_permissions` — a handful of lines
   where there are now 468.
4. `WorkflowsHelperPatch` is deleted. The plugin renders its own selector, so
   `options_for_workflow_select` stops being overridden — which dissolves F01 of
   the audit rather than fixing it.
5. The Deface overrides on the four core workflow views go, and INV-9's count
   changes in all three places that carry it.
6. Two links keep the two areas from feeling like two products: core's workflow
   screen points at the plugin's, and the plugin's points back.

**Expected result, stated so it can be checked rather than claimed:**

| | now | after |
| --- | --- | --- |
| Deface overrides | 15, in 12 files | 2 (both on `issues/_attributes`), or 4 if the bulk actions stay on core's `_form` |
| `workflows_controller_patch.rb` | 468 lines, six replaced actions | under 60 lines, five narrowed queries |
| shadowed core methods | 22 | about 13 |
| core helper prepends | 1 (`WorkflowsHelper`) | 0 |

## Measured result (2026-08-28, WP12 steps 4-8)

The subtraction landed. What the table above predicted against what was
measured, so that the ADR can be read as a claim that was checked:

| | predicted | measured |
| --- | --- | --- |
| Deface overrides | 2, or 4 if the bulk actions stay | **5 in 3 files** |
| `workflows_controller_patch.rb` | under 60 lines, five narrowed queries | **about 40 lines of code**, three actions and one finder |
| shadowed core methods | about 13 | 24 in the manifest, two fewer than before — see below |
| core helper prepends | 0 | **0** |

Three of the four differ from the prediction, and each for a reason worth
writing down:

- **Five overrides, not four.** The table counted the two bulk actions and the
  two on the issue form and forgot to count the cross-link its own Consequences
  section asks for.
- **`update` and `update_permissions` needed no predicate.** Decision 3 above
  names five actions; the write half of the pair already goes through
  `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions`, which the plugin's singleton patches
  route to its writers with `project_id` fixed at `nil` (INV-1). What the list
  missed instead is `find_statuses`, whose "used statuses only" query carries no
  `project_id` either.
- **The shadowed-method count barely moved.** The prediction assumed the copies
  disappear with the patch. They do not: `ProjectWorkflowRulesController` carries
  core's seven workflow actions and four of its private finders, because the
  plugin's screens *are* those screens now. Two digests went --
  `WorkflowsHelper#options_for_workflow_select`, which nothing shadows any more,
  and `WorkflowsController#find_trackers_roles_and_statuses_for_edit`, whose
  copy existed only to move work behind an authorization check that is now
  simply declared first. A copy is a copy wherever it is filed, and the drift
  gate follows it (`CoreMethodDigest::TARGETS`).

## Alternatives considered

- **Leave it as it is.** Defensible today: the anchors are tested on nine cells
  on every push, and nothing has broken. Rejected because the test proves the
  anchor matches *this* Redmine, and the plugin is meant to outlive several. The
  anchors that break on an upgrade are precisely the ones on views the plugin
  does not own.
- **Move the rules out of core's `workflows` table into a plugin-owned table**,
  which would remove the core-table migration, the destructive uninstall and the
  MySQL rebuild. **Rejected.** It would rewrite essentially everything and it
  would not remove the actual upgrade tax, which is the replacement of core's
  *query* methods — those have to be replaced either way. What it would cost is
  the cascade deletes that real foreign keys give today, the reuse of
  `WorkflowTransition` / `WorkflowPermission`, the reuse of core's matrix
  partial, and one-query resolution of both populations. ADR-001 stands.
- **Copy core's `workflows/_form` into the plugin** and own the grid outright.
  Not now: it would trade two anchors for a copied view that has to track core,
  which is the same tax in a different currency. Worth revisiting only if the
  bulk-action anchors ever stop matching.
- **One administration area, replacing core's.** Rejected: an administrator who
  does not use per-project workflows must go on seeing exactly the screen
  Redmine ships, and a plugin that replaces a core admin screen is a plugin
  nobody can uninstall safely.

## Consequences

- Two entry points in Administration instead of one. That is the price, and it is
  paid in navigation rather than in correctness. Cross-links in both directions.
- The eleven overrides and their assertions in
  `spec/integration/deface_overrides_spec.rb` are deleted, not rewritten. INV-9
  gets smaller and stays exactly as strict.
- A runtime anchor check becomes worth building. With fifteen anchors it would be
  a second test suite; with two it is a diagnostics-page line, and it closes the
  one gap ADR-002's drift check explicitly does not cover.
- The bulk-editing work of WP5 and the undo of WP6 move screens but do not change
  behaviour. Their specs move with them.
- This is a large diff for no user-visible change, which is exactly the kind of
  work that becomes impossible once there are installations to migrate. Doing it
  before the first rollout is the whole reason it is happening now.
