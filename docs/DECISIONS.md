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
| 2026-08-26 | Plugin patch hook | Patches are applied in the body of `init.rb`; the corrected `CLAUDE.md` row stands | Answered A. `Rails.application.config.to_prepare` in a plugin's `init.rb` is a silent no-op: `:add_to_prepare_blocks` has already consumed `config.to_prepare_blocks` by the time Redmine's `PluginLoader` loads the file, and following the old wording disabled the plugin entirely while the suite stayed green. Considered and rejected: reverting the table and recording the trap elsewhere. |
| 2026-08-26 | Request-scoped cache | `ActiveSupport::CurrentAttributes`, as `RedmineProjectWorkflows::Current` | Answered A. Rails resets it around every request and job on 5.1, 6.1 and 7.0, and it adds no dependency. Considered and rejected: adding `request_store` to the plugin's own Gemfile (Redmine 7.0 dropped the gem), and dropping the cache entirely (one extra query per issue where a list renders many). |

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
| 2026-08-26 | WP0 | An entry a writer rejects is dropped **before** the delete, not only before the insert | Core destroys the row and then fails to create the replacement, so an unacceptable value clears the rule it names. Dropping the whole entry means a tampered or malformed request changes nothing. It also repairs a case core gets wrong: a transitions cell left entirely at "no change" arrived as an empty rule hash, which still contributed to the delete and inserted nothing. |
| 2026-08-26 | WP0 | Permission field names are narrowed to existing `IssueCustomField` ids | Core accepts any run of digits. The matrix only ever offers the trackers' own custom fields, so requiring the field to exist cannot reject anything the UI submits. |
| 2026-08-26 | WP0 | An invalid copy **target** is a validation error on the form; an invalid matrix **selector** value is a 404 | They are two different controls with two different sets of valid values (`all` belongs to the selector, never to the copy form). One is a form submission the operator can correct; the other is a hand-edited URL. |
| 2026-08-26 | WP0 | `apply_patches` is called in the body of `init.rb`, not from a hook | Redmine's `PluginLoader` already loads every `init.rb` from inside a `to_prepare` block, so the body *is* the reload hook. `config.to_prepare` there is a silent no-op — see the correction to `CLAUDE.md`'s forbidden-constructs table. |
| 2026-08-26 | WP0 | The request-scoped cache is `ActiveSupport::CurrentAttributes`, not `RequestStore` | Redmine 7.0 no longer bundles `request_store`, so `RequestStore` is not available on every supported version. `CurrentAttributes` is reset by the executor on all three. |
| 2026-08-26 | WP0 | `spec/spec_helper.rb` no longer applies the patches itself when the boot did not | That fallback hid a change that left the plugin doing nothing in a real installation while the suite stayed green. `spec/plugin_conventions_spec.rb` asserts the boot instead. |
| 2026-08-26 | WP0 | No grep-style scanner example was added, per the existing choice | The `Thread.current` removal is covered behaviourally instead. Jan's "Invariant enforcement" entry stands; it says revisit, and this was not the occasion. |
| 2026-08-26 | dev | `dev/setup.sh` and `dev/run.sh` put rbenv's **shims** on `PATH`, not just rbenv itself | `command -v rbenv` succeeding does not mean the shims are on `PATH`; without them the ambient Ruby ran and the failure surfaced much later, as a Gemfile Ruby requirement. |

| 2026-08-26 | WP1 | The scope table's unique index ships with the table, in migration 004 | `design.md` specifies it as part of the table, and the backfill has to produce unique rows anyway. The implementation plan listed it under WP2; that item is therefore already delivered. |
| 2026-08-26 | WP1 | Foreign-key columns are `:integer`, not Rails' default `:bigint` | Redmine's own primary keys are 4-byte integers and MySQL refuses a foreign key whose column width differs from the column it references. |
| 2026-08-26 | WP1 | The backfill stamps `CURRENT_TIMESTAMP`, not a quoted Ruby `Time` | PostgreSQL will not cast a text literal to a timestamp inside a `SELECT` list, and the casts that would work are spelled differently on MySQL. Rails puts every supported adapter's session in UTC. |
| 2026-08-26 | WP1 | `Issue#new_statuses_allowed_to` and `#workflow_rule_by_attribute` **always** take the plugin's path, inheritance included | Core's queries carry no `project_id` predicate, so calling `super` for an inheriting project would read its neighbours' rows — a breach of INV-4 and a real defect, because the old system-wide `override_active?` guard was the only thing hiding it. Both method bodies are byte-identical in Redmine 5.1, 6.1 and 7.0, so reproducing them is safe; `override_active?` is gone from both query services. |
| 2026-08-26 | WP1 | "Enable" acts only on the combinations that currently inherit | Makes the action idempotent. Re-copying the generic workflow over a project that already has one would silently discard the operator's edits, and there is no undo before WP6. |
| 2026-08-26 | WP1 | "Empty the matrix" acts only where a scope already exists | Emptying a matrix a project does not own would read as a change while leaving it inheriting — the very confusion the scope table ends. |
| 2026-08-26 | WP1 | The scope panel reuses the `div.autoscroll` anchor rather than introducing a new one | That element already carries an override on both matrix screens and exists verbatim in all three supported versions, so the risk INV-9 guards against does not grow. `design.md`'s table now lists seven overrides and `spec/integration/deface_overrides_spec.rb` asserts each. |
| 2026-08-26 | WP1 | The three actions live on their own routes under `/project_workflow_scopes` | Plugin routes are drawn after core's, so a path under `/workflows` could shadow one. Buttons are `link_to ... method:`, which core itself uses, because a `button_to` form would nest inside the matrix form. |
| 2026-08-26 | WP1 | The scope actions are administrator-only for now | WP4 adds `manage_project_workflow` and the project settings tab. Until then `require_admin` satisfies INV-7 trivially, and the controller is already written so that only the authorization line has to change. |
| 2026-08-26 | WP1 | Bulk deletes are expressed as an OR of exact (project, tracker, role) triples, in batches of 500 | The cross product of the three id lists would reach combinations the operator did not name. The copy in "enable" stays one statement per combination: a copy has to name its target, and the count is what the operator selected. |
| 2026-08-26 | WP1 | `Resolver.scoped?` was written and then deleted before the commit | It had no caller once the `override_active?` gate went. WP3 or WP4 can add it back when something needs it; `ScopeState` answers the question the screens actually ask. |
| 2026-08-26 | WP1 | The backfill has its own CI gate, `dev/check-backfill.sh`, run before the suite | Migration bookkeeping is wiped once the suite starts, so a backfill test cannot live in RSpec. The script seeds the rules an installation from before ADR-001 would have, takes migration 004 down and up, and checks the scopes that come back. |
| 2026-08-26 | WP1 | Two README paragraphs invalidated by WP0 and WP1 were corrected now rather than left for WP7 | WP7 still owns the rewrite. What was removed was a warning about a JavaScript error WP0 fixed, pointing at a characterization file that no longer exists, and a usage step that described the implicit model ADR-001 replaced. |

## Open — for Jan

*(Nothing open. Items land here with their options, a plain-language
explanation of each and a recommendation, while the build continues on the
safest default.)*
