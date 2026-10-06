# Findings — the copy form, noticed while fixing the Codex run

- **Run:** 2026-08-26
- **Reviewed:** `claude/dev` at `db381fc`, while fixing `2026-08-26-codex.md`
- **How:** noticed while widening F01's guard to the requests that carry no
  project parameter, and confirmed by reading the rendered form's markup and
  `project_context?`. Recorded rather than fixed: it is a behaviour decision on
  a screen the Codex run did not raise it for, and `CLAUDE.md` says an
  out-of-scope defect goes into a findings file, not into the diff.

---

### C01 — The copy form silently copies into the generic workflow when no target project is selected

- **Status:** fixed
- **Severity:** major
- **Confidence:** confirmed
- **Category:** correctness, ux
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_patch.rb`,
  `#duplicate` (`return super unless project_context?`);
  `lib/redmine_project_workflows/patches/workflows_controller_project_selection.rb`,
  `#project_context?`;
  `app/views/redmine_project_workflows/_copy_project_selector.html.erb`
- **Invariant touched:** none

**What is wrong**

The copy form's target project control is a `multiple` select whose blank option
is disabled, and nothing is preselected. A `multiple` select with no option
selected submits **no parameter at all**. If the source project control is also
left at its blank default, none of `project_id`, `source_project_id` or
`target_project_ids` is present, so `project_context?` is false and `#duplicate`
hands the request to core — which copies the source workflow into the **generic**
workflow and reports "Successful update".

The plugin's own validation says a target project is required: in project context
`resolved_target_project_ids.blank?` raises `error_workflow_copy_target`, whose
English text is "Please select target trackers, roles, **and projects**." The one
path where the administrator selected no project at all is the one path that does
not reach it.

**Why it matters**

An administrator opens *Administration → Workflow → Copy*, picks a source tracker
and role, picks target trackers and roles, and misses the target project selector
(it is the third control in the target fieldset and has no default). The copy runs
against the generic workflow: every rule of the target (tracker, role) pairs is
deleted and replaced with the source's. The generic workflow is the one every
project that has not overridden it inherits, so a slip on one control rewrites the
workflow of the whole installation, with a success message and no confirmation.

**How I verified it**

Read `_copy_project_selector.html.erb` (the blank option carries `disabled: true`
and `selected: false` when `disable_blank` is set, and no other option is
preselected), then `project_context?`, which reads the three parameters rather
than the resolved list. A browser omits an unselected `multiple` select from the
submission entirely. Not executed as a controller example — writing one would be
writing the regression test for a fix that has not been decided.

**Suggested direction**

Two shapes, and the choice is Jan's rather than a fixer's, because both change
what an administrator sees:

- Treat "no target project" as the validation error the wording already promises,
  and reject the request. Safest for data; it also means a bare core-shaped
  request to `/workflows/duplicate` (no plugin parameters at all) stops working,
  which is a visible change for any script or plugin that posts one.
- Preselect *Generic* in the target project selector, so the form always submits
  a target and the copy that runs is the copy the form shows. Keeps core's request
  shape working; makes the destructive default the visible one.

Whichever is chosen, the source project selector deserves the same look: it
defaults to blank, which `#duplicate` reads as the generic workflow.

**Resolution:** Fixed as **option B**, answered by Jan on 2026-08-26. The target
project control now preselects *Generic* when nothing else is selected, so the
form always submits a target and the copy that runs is the copy the form shows.
One local on `_copy_project_selector.html.erb` (`default_global`), passed by the
target selector's override only.

Option A was not taken and is not needed now: with a target always submitted,
every submission from the plugin's own form carries project context and is
validated by `#duplicate` rather than handed to core. A **hand-built** request
carrying no plugin parameter at all still reaches core and still rewrites the
generic workflow — that is Redmine's own behaviour, it is now the only way to
reach it, and A remains available if Jan ever wants it closed too. So does
deliberately clearing the control with ctrl-click, which is the same request.

The **source** project control was deliberately left alone. Blank there already
means the generic workflow, it destroys nothing, and the source tracker and role
beside it are blank-by-default as well — that is core's own convention for "not
chosen yet", and making this one control differ would be the inconsistency rather
than the fix.

Verified red on the old code by restoring both changed files to their `e9f2443`
state and re-running: one of the three new view examples fails, the one asserting
*Generic* is preselected. The other two are regression guards that must pass on
both sides, and do — the source control is untouched, and a target selection that
was submitted is kept rather than having *Generic* added to it. 585 examples / 0
failures on Redmine 5.1, 6.1 and 7.0 on PostgreSQL 16; RuboCop clean.

The first version of these examples asserted `selected="selected" value="global"`
as one string. It caught the real case but made the two guards **vacuous**:
`content_tag` writes `value` before `selected` and
`options_from_collection_for_select` writes them the other way round, so a
"not_to include" naming both in one order could never have failed. They read the
selected values off the markup now instead of matching a string against it.
