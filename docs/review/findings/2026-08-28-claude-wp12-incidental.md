<!-- Not a review run. One finding noticed while implementing WP12 steps 1-3 and
     deliberately not fixed there: CLAUDE.md says an out-of-scope defect goes into
     a findings file rather than into the diff. -->

# Incidental finding — 2026-08-28 — WP12 steps 1-3

- **Reviewer:** Claude Code, while implementing WP12 (not a review run)
- **Commit reviewed:** `56f41fc`
- **Ran the test suite:** yes — Redmine 5.1 (Ruby 3.2.6), 6.1 and 7.0 (Ruby 3.3.6), PostgreSQL 16; 963 examples, 0 failures on each
- **Scope covered:** nothing systematic. This is one thing noticed while moving `field_permission_tag` out of `Patches`.
- **Scope NOT covered:** everything else. Do not read this file as a review.

## Summary

While moving the workflow matrix cell helpers to `ProjectWorkflowMatrixHelper`,
the helper spec went red with `NoMethodError: field_required?`. That is a spec
problem and was fixed in the same commit — but it points at a real gap behind
it: `field_required?` is a method of Redmine's own that this plugin *calls*
without replacing, and the compatibility manifest does not declare it. ADR-002
built a mechanism for exactly that case and this call is not in it.

**Counts:** blocker 0 · major 0 · minor 1 · nit 0 · question 0

---

### F01 — `WorkflowsHelper#field_required?` is called but not a declared dependency

- **Status:** fixed 2026-08-29 (WP14) — see Resolution
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** operability
- **Where:** `app/helpers/project_workflow_matrix_helper.rb:34` (and, before ADR-003 moved it, `lib/redmine_project_workflows/patches/workflows_helper_patch.rb`), against `lib/redmine_project_workflows/compatibility.yml`'s `dependencies:` list
- **Invariant touched:** none

**What is wrong**

`field_permission_tag` calls `field_required?`, which the plugin does not
define. It reaches it through core's `WorkflowsHelper`, which is in the helper
chain of every controller that renders a matrix. That makes it precisely what
ADR-002 calls a *declared dependency*: a core method the plugin depends on and
does not shadow, so `super_method` cannot find it and the shadow half of the
drift gate never sees it. `Issue#roles_for_workflow` is in the manifest for this
reason; this one is not.

The gap predates WP12 — the patch called the same method — so nothing regressed
here. It was simply invisible until the move made the call site obvious.

**Why it matters**

If a future Redmine changes what `field_required?` answers (its body is a
hard-coded list: `project_id tracker_id subject priority_id is_private`, plus
`is_required?` for a custom field), every field-permissions matrix in the plugin
starts offering **Required** for a field that is already required, or omitting it
for one that is not — on the project screens as well as the administration ones.
Nothing would report it: the plugin's own specs assert the plugin's expected
answers, and a manifest that does not list the method cannot notice its body
changed. If core *removes* it, `missing_dependencies` would not report that
either, and the screen raises `NoMethodError` at render time.

**How I verified it**

Read `Compatibility.dependencies` in `lib/redmine_project_workflows/compatibility.yml`
and confirmed `WorkflowsHelper#field_required?` is absent; read core's definition
in all three checkouts under `.redmine/` (`app/helpers/workflows_helper.rb:45` on
7.0) and confirmed it is byte-identical across 5.1, 6.1 and 7.0. Not fixed, and
no test written.

**Suggested direction**

One line in the manifest's `dependencies:` list and three digests, measured with
`dev/measure_compatibility.rb` per host — the script prints whatever
`CoreMethodDigest` discovers, so no code change is needed. Worth doing the same
sweep for the whole plugin at once rather than for this one method: the question
"which core methods do we call that we do not replace?" has been answered by
hand twice now, and a grep of the plugin's calls against
`WorkflowsHelper.instance_methods` and its siblings would answer it properly.

**Resolution:** Fixed, and the finding's own second suggestion — "worth doing the
same sweep for the whole plugin at once" — is what carries it, because doing it
turned one entry into two.

`WorkflowsHelper#field_required?` is now in the manifest's `dependencies:` block
with the reasoning above, and its digest is recorded for all three verified
minors (identical on 5.1, 6.1 and 7.0: `2a5e8977…`), measured with
`dev/measure_compatibility.rb` on each host.

The sweep is `spec/plugin_conventions_spec.rb`, "watches every WorkflowsHelper
method the plugin calls": every method core's `WorkflowsHelper` defines and the
plugin's own `app/` or `lib/` sources mention has to be watched — as a shadow
discovered from a patch module, or as a declared dependency. **It found a second
one on its first run:** `WorkflowsHelper#options_for_workflow_select`, called by
the plugin's own selection form on *Administration → Project workflows* and no
longer shadowed since ADR-003 deleted `WorkflowsHelperPatch`. It is the control
that decides what *(All)* means and when a selector becomes a multi-select, so a
change to it changes what an administrator can select on a screen the plugin
owns. Declared and digested the same way (`fe603bed…`, also identical across the
three).

Deliberately textual rather than a call graph: a coincidence of naming costs one
manifest entry, while the failure it prevents is a screen quietly offering the
wrong control on a Redmine nobody has read yet.

The example is red on the old manifest — verified by deleting both declarations
and re-running: *"the plugin calls WorkflowsHelper#field_required? and nothing
watches it."* The digest table is 26 entries per minor, was 24, and
`spec/upstream/` is green on 5.1 and 7.0.
