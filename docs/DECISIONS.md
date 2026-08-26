# DECISIONS — the ledger

> Append-only. Three sections: what a session decided on its own, what Jan
> decided, and what is still waiting on him. A build never waits for an open
> choice — there is always a safe, reversible default in place. When Jan
> answers, the item moves up to "Decided (Jan)" with the date rather than being
> edited in place.

## Decided (Jan)

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-26 | Inheritance | A project scope **replaces** the generic workflow | Considered and rejected: additive overrides (cannot remove anything without negative rules) and a per-scope mode switch (doubles the semantics in resolver, matrix and overview). |
| 2026-08-26 | Scope unit | Separate scopes for transitions and field permissions | Matches the two separate admin screens: overriding transitions must not force taking over field permissions. |
| 2026-08-26 | Project hierarchy | No inheritance between projects | Keeps resolution to one indexed lookup on the hot path. Project trees are served by copying to subprojects instead. |
| 2026-08-26 | Who administers | Project administrators too, via project settings | Chosen over admin-only. Adds a permission model and a project-scoped controller — the only place non-admins write workflow data. |
| 2026-08-26 | Permissions | Two: `view_project_workflow` and `manage_project_workflow` | Managing includes enabling a project's own workflow and returning it to inheritance. Considered and rejected: reserving enable/disable for the system administrator as a governance boundary. |
| 2026-08-26 | Project screen | The same matrix, narrowed to the project | Only trackers enabled in the project and roles with members there. |
| 2026-08-26 | Enabling a scope | Operator chooses; copy of the generic workflow preselected | With replacing semantics an accidental empty scope freezes every issue in the project, so the safe option is the default one. |
| 2026-08-26 | `rolled_up_statuses` | Drop the role filter, as core has none | Keeping it left the status filter empty for projects without members. A wider list is less harmful here than a narrower one. |
| 2026-08-26 | Copying a role or tracker | Project rules travel with it | A copied role should be a working copy. Considered and rejected: a checkbox in the form (two more Deface anchors to maintain). |
| 2026-08-26 | Overview | Repair the summary page **and** add an inventory | The summary counts wrong today and has to be fixed anyway; the inventory answers "which projects deviate", which the summary's tracker × role grid cannot. |
| 2026-08-26 | Bulk editing | Row and column actions Yes / No / Unchanged | Includes the CSS-class repair that makes core's own toggles reach mixed cells. Full selection UI (rectangle, drag) is out of scope. |
| 2026-08-26 | Extras in scope | Compare with generic, audit columns, undo before save | Workflow templates are out of scope. |
| 2026-08-26 | Delivery | One pull request, built from self-contained commits | The diff will be large; commit granularity is what keeps it readable. |
| 2026-08-26 | Supported versions | Redmine 5.1, 6.1 and 7.0 | 5.1 is in production; 7.0 already passes. The cost is version-conditional code for SVG sprites, kept behind one helper. |
| 2026-08-26 | Agent framework | Adopt the `redmine_ai_triage` framework, adapted | Full scope: CLAUDE.md with plugin-specific invariants, the three memory files, the review loop, one design document and one ADR, three extra CI gates. |
| 2026-08-26 | Development branch | One pinned branch, `claude/dev` | Overrides the per-session branch name the environment prescribes. Without a pin the work migrates to a new branch every session. |
| 2026-08-26 | Documentation language | English throughout | Including `STATE.md`, `DECISIONS.md` and the session report — differs from `redmine_ai_triage`, where those three are Dutch. |
| 2026-08-26 | Invariant enforcement | Text in CLAUDE.md, no scanner spec | Considered and rejected: a spec that greps for forbidden constructs and fails the build, as `redmine_ai_triage` does. Revisit if an invariant is breached in practice. |

## Decided (autonomous)

| Date | Package | Decision | Why |
| --- | --- | --- | --- |
| 2026-08-25 | harness | The plugin is **copied** into the Redmine host, not symlinked | The specs resolve `config/environment` relative to their own real path; through a symlink that resolves outside the host and every spec fails to load. |
| 2026-08-25 | harness | `spec/characterization/` holds examples that pass while documenting wrong behaviour | Makes the defect list mechanical: the plan is finished when the directory is empty. The header of each file says so, so nobody reads them as a specification. |
| 2026-08-25 | harness | `spec/integration/` asserts each Deface override against the rendered page | An unmatched override produces no error, only a missing selector; it has to be caught per Redmine version. |
| 2026-08-25 | CI | One matrix workflow on push and pull request, replacing two manual-dispatch workflows | The old ones had never run automatically, so "the suite is green" was never evidence of anything. |
| 2026-08-26 | lint | RuboCop config adapted from `redmine_ai_triage`, close to Redmine core's own | A plugin that reads like the host application is easier to contribute to. `Naming/VariableNumber` is off: Redmine's fixtures are numbered and specs address them by those names. |
| 2026-08-26 | lint | Existing offences grandfathered in `.rubocop_todo.yml` (181, all file excludes) | Keeps the gate meaningful for new code today. `inherit_mode: merge: Exclude` is required, otherwise the main config's excludes replace the todo's instead of adding to them. WP7 works the list down. |
| 2026-08-26 | lint | The linter lives in `.github/lint/Gemfile`, outside the plugin root | Redmine's Gemfile evals `plugins/*/Gemfile`; the linter has no business in the host application's runtime bundle. |
| 2026-08-26 | CI | Migration reversibility (up → 0 → up) runs **before** the suite | `maintain_test_schema` reloads `db/schema.rb` when the suite starts and wipes the plugin's migration bookkeeping; after that `VERSION=0` silently does nothing and the check proves nothing. Borrowed from `redmine_ai_triage`, which paid for this one. |
| 2026-08-26 | CI | `zeitwerk:check` added as a gate | Redmine pushes each plugin's `lib/` into the main Zeitwerk autoloader with eager loading, so a misnamed constant only breaks in production. Verified passing on 7.0 today. |
| 2026-08-26 | docs | No `model.json`, `phasing.md`, `spikes/` or `technical-spec.md` | `redmine_ai_triage` needs them for a 25-task LLM pipeline. This plugin has one feature; a second planning document beside an eight-package plan would only be able to disagree with it. |

## Open — for Jan

*(Nothing open. Items land here with their options, a plain-language
explanation of each and a recommendation, while the build continues on the
safest default.)*
