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
| 2026-08-26 | Copy screen, no target project (finding C01) | **B — preselect *Generic* in the target project control** | A multiple select with nothing selected submits no parameter at all, so a copy form that showed nothing there still ran against the generic workflow, reported success, and said so nowhere. Preselecting it makes the destructive default the visible one and costs no request shape: option A (refusing the request) would have stopped a bare Redmine-shaped copy request working, and stays available. The **source** project control keeps its blank default — blank there already means the generic workflow, destroys nothing, and the source tracker and role beside it are blank-by-default too, which is core's own convention for "not chosen yet". |
| 2026-08-26 | Supported versions | Redmine 5.1, 6.1 and 7.0 | 5.1 is in production; 7.0 already passes. The cost is version-conditional code for SVG sprites, kept behind one helper. |
| 2026-08-26 | Agent framework | Adopt the `redmine_ai_triage` framework, adapted | Full scope: CLAUDE.md with plugin-specific invariants, the three memory files, the review loop, one design document and one ADR, three extra CI gates. |
| 2026-08-26 | Development branch | One pinned branch, `claude/dev` | Overrides the per-session branch name the environment prescribes. Without a pin the work migrates to a new branch every session. |
| 2026-08-27 | Bulk tracker change across many projects (finding G02) | **A for now, B if it becomes an issue later** | Two statements per distinct project against core's one for the whole selection: 22 for ten issues in ten projects, 2 for ten in one, measured twice. Left as it is, because the action is rare and an ordinary issue save asks nothing. When it is ever felt, the fix is **B** — resolve the whole `edited_issues` set in one call, which means patching `IssuesController`. The half measure **C** (one shared answer for the projects that have not taken the tracker over, ~11 instead of 22) was **not** chosen and is not a cheap substitute for B; it would add a second cache to a path every issue save touches and leave the cost linear in project count. B's price is one more copied core method in F03's digest table, on a controller that differs between 5.1 and 6.x, so it needs the table re-measured on all three minors. |
| 2026-08-26 | Documentation language | English throughout | Including `STATE.md`, `DECISIONS.md` and the session report — differs from `redmine_ai_triage`, where those three are Dutch. |
| 2026-08-26 | Invariant enforcement | Text in CLAUDE.md, no scanner spec | Considered and rejected: a spec that greps for forbidden constructs and fails the build, as `redmine_ai_triage` does. Revisit if an invariant is breached in practice. |
| 2026-08-26 | Plugin patch hook | Patches are applied in the body of `init.rb`; the corrected `CLAUDE.md` row stands | Answered A. `Rails.application.config.to_prepare` in a plugin's `init.rb` is a silent no-op: `:add_to_prepare_blocks` has already consumed `config.to_prepare_blocks` by the time Redmine's `PluginLoader` loads the file, and following the old wording disabled the plugin entirely while the suite stayed green. Considered and rejected: reverting the table and recording the trap elsewhere. |
| 2026-08-26 | Request-scoped cache | `ActiveSupport::CurrentAttributes`, as `RedmineProjectWorkflows::Current` | Answered A. Rails resets it around every request and job on 5.1, 6.1 and 7.0, and it adds no dependency. Considered and rejected: adding `request_store` to the plugin's own Gemfile (Redmine 7.0 dropped the gem), and dropping the cache entirely (one extra query per issue where a list renders many). |
| 2026-08-26 | The "only used statuses" label | Leave core's wording alone | Answered A. The filter now means "the statuses the selected workflow uses", and with a project selected that project's workflow is what "this tracker" refers to there anyway. Considered and rejected: overriding the text when a project is selected, which needs two more Deface anchors and a spec for each (INV-9) to change "used by this tracker" into something barely different. |
| 2026-08-26 | A unique constraint on `workflows` | No; keep `project_id` nullable and repair with the rake task | Answered A. The only visible symptom of a duplicate row is a matrix cell drawn as a mixed dropdown instead of a checkbox, and `rake redmine_project_workflows:deduplicate_workflow_rules` clears that in seconds. The residual race — two administrators saving the same matrix at the same instant — stays, and is core's as much as the plugin's. Considered and rejected: `project_id` NOT NULL with 0 for the generic workflow, which would make a plain unique index work on all three databases but changes what every query and `docs/design.md` mean by "generic", and would need an ADR. |
| 2026-08-26 | `Issue#project=` and the status (finding G03) | Leave it as Redmine already behaves | Answered A. An issue moved into a project whose workflow does not use its status keeps that status and, in that project, has no transition it may make. Core has the same asymmetry, so nothing here is a regression; what per-project workflows change is that it can be reached without an administrator editing anything. Considered and rejected for now: resetting the status the way `#tracker=` does (it sits on the path of every issue save and every bulk move, and `safe_attributes=` assigns `project_id` before `tracker_id` on purpose, so a wrong order would reset statuses that should have been left alone) and refusing the move outright. |
| 2026-08-26 | The builtin roles on the project screen | The project screen offers only the roles that have members in the project | Answered A. *Non member* and *Anonymous* go on following the generic workflow, and a system administrator can still give a project its own workflow for them from Administration → Workflow. Considered and rejected: listing them on public projects, where those roles really do act on the issues. |
| 2026-08-26 | Where the settings tab attaches | `ProjectsController.helper`, never `ProjectsHelper.prepend` | Raised by Jan from `redmine_ai_triage`'s K-29. Many Redmine plugins take `project_settings_tabs` over with an alias chain; `alias_method` resolves through `ProjectsHelper.ancestors`, so with anything prepended there the neighbour copies *our* method and the copy's `super` finds nothing above `ProjectsHelper` — core's own method drops out and every settings page raises `NoMethodError`. Attaching to the controller's helper chain is immune by construction, in either load order. |
| 2026-08-26 | WP8's flowchart | **C**: the local view only — "from here", and no drawing | Answered C. The status the issue is in, the statuses it can move to, what each move requires (anyone / only the author / only the assignee), and the statuses that can lead into this one. Considered and rejected for now: A) a layered SVG diagram, which is what Jira draws and needs a layout pass of the plugin's own plus a table beside it for screen readers, and B) a read-only copy of the administration tick-box grid. C is A's data without the layout, so A stays buildable on top of it later. |
| 2026-08-26 | Order of the last two packages | **WP7 first, then WP8** | Jan's call, and WP8 will be started in a session of its own. So the release pass covers what exists at that point and WP8 carries its own README paragraph, CHANGELOG line and locale keys. |
| 2026-08-26 | Declared minimum Redmine version | **5.1**, raised from 5.0 | Answered A. Nothing had ever tested 5.0 and the README said so. Known limit, recorded so nobody mistakes the floor for a claim: 5.2, 6.0, 6.2 and 7.1 still install and none of those is in CI either, so the README's Compatibility section — which names the nine cells that run on every push — remains the honest answer. Considered and rejected: putting 5.0 back and going on warning that it is untested. |
| 2026-08-26 | WP8 must name the workflow it is describing | The panel says whether this issue is governed by the project's own workflow or the generic one, per role, and links to where it is edited | Raised by Jan while reviewing WP8's spec, and it is the first thing somebody debugging "why can I not close this issue" needs. Nothing on the issue form says it today: core has no concept of a project workflow, and WP8 is the first thing the plugin puts on that form at all. |
| 2026-08-26 | Bulk editing (field permissions) | The field-permissions matrix keeps only core's `»` copy control — no row or column actions | Answered **A** the same day it was raised. The transitions matrix is the one with the clicking in it; core has no row or column toggles on the field-permissions matrix to repair, its cells are four-valued rather than yes or no, and `»` already covers "the same from here on". B — the same three actions adapted to four values — stays available as a small work package of its own if somebody actually wants it. |
| 2026-08-26 | WP8 stays inside the 0.1.0 release | **A**: one release containing everything; no 0.2.0 | Answered **A**. 0.1.0 had never been tagged or published and `main` was still pre-WP1, so the first release anybody can install already contains WP8; a 0.2.0 heading would have described an upgrade path from a version that never existed. Considered and rejected: bumping `init.rb` to 0.2.0 with a heading of its own — still one line plus one heading if a reason appears, and `spec/plugin_conventions_spec.rb` asserts the version and the newest changelog heading agree, so it cannot be done by halves. |
| 2026-08-26 | All eight locale files are translated | **A**: keep translating all eight, and `CLAUDE.md` now says so | Answered **A**. The rule in `CLAUDE.md` said the six beside `en` and `nl` merely carried the keys; the files had not matched that for some time, and WP8 followed the files. `en` and `nl` stay the authoritative pair. The cost is recorded rather than glossed: the six are unreviewed translation *presented as* translation, so a wrong word reads as a decision rather than as a gap, and `spec/locales_spec.rb` can assert key parity but never that a translation is right. Considered and rejected: **B**, keeping the rule and leaving new keys in those six in English and marked — honest and cheap, but it would have meant un-translating six files that are already done. Raised by the fresh-subagent review of WP8. |

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
| 2026-08-26 | WP1 | ~~The backfill stamps `CURRENT_TIMESTAMP`, not a quoted Ruby `Time`~~ **SUPERSEDED 2026-08-27, both halves wrong** — see the entry under the 2026-08-27 review run and finding F09. `CURRENT_TIMESTAMP` is UTC only on PostgreSQL; and PostgreSQL *does* coerce a bare quoted literal to a timestamp column in a `SELECT` list, measured on 16.13. | The original reasoning: "PostgreSQL will not cast a text literal to a timestamp inside a `SELECT` list, and the casts that would work are spelled differently on MySQL. Rails puts every supported adapter's session in UTC." |
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
| 2026-08-26 | WP2 | `StatusListQuery` works on (project, tracker) **pairs**, not one project at a time | A project tree has to resolve every project against its own scope (INV-6), and looping the old single-project entry point would have made the query count grow with the size of the tree. The pairs API costs two queries whatever the tree looks like, and the single-project call is now a thin wrapper over it. |
| 2026-08-26 | WP2 | `role_ids: nil` in `StatusListQuery` now means "no role filter", not "every role that considers the workflow" | Core's own queries in these places carry no role predicate, and enumerating roles was what made a member-less project answer with nothing. It also drops a `Role.all` load from the path. Where a role predicate genuinely belongs — the matrix screens — the caller passes one. |
| 2026-08-26 | WP2 | The role filter in `Issue#new_statuses_allowed_to`'s status lookup was removed, reversing a WP1 detail | That lookup decides whether an issue *keeps* its status across a tracker change. A status only another role's rules use is still the issue's status, and with the filter a Resolved issue was quietly offered the new tracker's default instead. Core has no filter there. |
| 2026-08-26 | WP2 | `Issue#tracker=`'s status list is cached per (project, tracker) for the length of the request | Core memoises its equivalent on the Tracker instance, and core's own `tracker_id=` builds a fresh instance per issue — so a bulk tracker change queried once per issue. The cache lives in `RedmineProjectWorkflows::Current` and is cleared by `Resolver.reset_cache!`, which now clears every cache that reads the scope table rather than only its own. |
| 2026-08-26 | WP2 | Role and tracker duplication get their own patches; `.copy_one` is left generic-only | The administration copy screen falls through to core's `.copy` when no project is selected, and the two methods are indistinguishable from inside `.copy`. Folding the project rules in there would have turned "copy the generic workflow" into "copy every project's workflow too". `Role#copy_workflow_rules` and `Tracker#copy_workflow_rules` are core's only other callers and are the two that mean "duplicate this entirely". |
| 2026-08-26 | WP2 | A copied role or tracker inherits the source's scopes exactly, an own **empty** workflow included | Dropping an empty scope would silently return that combination to the generic workflow, which is the collapse INV-3 forbids. Core only ever calls these on a freshly created role or tracker, so nothing existing is disturbed. |
| 2026-08-26 | WP2 | No unique index on `workflows`; a `rake` repair task instead | The key needs `project_id` and `field_name`, both nullable, and PostgreSQL, MySQL and MariaDB all treat NULLs in a unique index as distinct — the generic rows would not be constrained at all. See the "Open" item below for the one option that would work. |
| 2026-08-26 | WP2 | The duplicate sweep deletes **exact** duplicates only | Two field permissions that agree on everything but the rule are a contradiction, not a duplicate; picking one would be answering a question only an administrator can answer. |
| 2026-08-26 | WP2 | Migration 005 drops two of the four plugin indexes on `workflows` | One has the same columns as another with role and tracker swapped, which decides nothing for equality predicates; the other is a strict prefix of a third. Every index is paid for on every insert, and a workflow save inserts a whole matrix. Reversible: `down` puts both back so 001 and 002 can still remove them. |
| 2026-08-26 | WP2 | `IssueStatus.new_statuses_allowed` and `WorkflowPermission.rules_by_status_id` are left project-blind | Core no longer reaches either once the plugin is installed, and the first has no project in scope to narrow it with. Recorded in `design.md` so a future plugin author is not surprised. |
| 2026-08-26 | WP2 | Every write that changes a rule resets the request caches, not only the writes that change a scope | `StatusListQuery`'s cached status list is derived from the rules, so `clear_rules`, a project save into an existing scope, a generic save, the two raw copy statements and the duplicate sweep all had to reset it as well. The comment on `Current` said the caches depended on the scope table; that was the contract, and the code did not meet it. |
| 2026-08-26 | WP2 | The 404 for an unresolvable project id moves out of core's pre-authorization callback into the five actions | Rendering from a `before_action` halts the chain, so the 404 was answered before `require_admin` ran and project ids could be enumerated anonymously (finding G01). Every action that needs the invalid ids already runs after authorization. Considered and rejected: deferring it to WP4, and prepending a second `require_admin` of the plugin's own (which duplicates a core callback and has to be kept in step with it). |
| 2026-08-26 | WP2 | Duplicating a role or tracker is one `INSERT ... SELECT` per (tracker, role), carrying `project_id` through | One statement per project was 381 round trips for three trackers and thirty overriding projects, inside one transaction. Carrying the column through instead of substituting it moves the generic rows and every project's together. |
| 2026-08-26 | WP2 | The scope copy is raw SQL with a `NOT EXISTS` guard, in its own service | `create!` per project doubled the round trips again. The SQL is justified as `copy_generic_to_project`'s is: every value is a column of an existing row or an id resolved from the database (INV-2). It lives in `Services::ScopeCopier` rather than `ScopeWriter` because `ScopeWriter` holds the three actions of INV-3 and was over RuboCop's class-length limit; the two of them together are still the only places that create or remove a scope. |
| 2026-08-26 | WP2 | `ProjectWorkflowScope.author_id_for` moved to the model | Two services now stamp the audit columns, and who counts as the author of a scope row is the table's rule rather than either writer's. |
| 2026-08-26 | WP2 | Each of the eight Deface overrides gets an assertion only it can satisfy | The selector and the hidden field both render `project_id[]`, so one assertion covered two overrides and either could have stopped matching unnoticed — which is exactly what INV-9 exists to prevent. The count was also wrong in two documents (`CLAUDE.md` said five, `design.md` tabulated seven). |
| 2026-08-26 | WP2 | `StatusListQuery` raises on a malformed pair rather than answering `[]` | `to_i` turned a missing tracker id into 0, and a flat pair list into one pair per element with tracker 0 — a wrong answer with no error. |
| 2026-08-26 | WP2 | `StatusListQuery.status_ids_for_project` deleted | Nothing outside its own spec called it once `status_ids_for_pairs` and `effective_status_ids` existed, so the specs were testing a shim. |
| 2026-08-26 | WP2 | Migration 005 declines to drop anything if migration 002's index is missing | Migration 003's foreign key needs an index with `project_id` leftmost and InnoDB refuses to drop the last one. Verified by removing 002's index by hand and watching 005 say so and leave both in place. |
| 2026-08-26 | WP2 | The cross-project bulk tracker change stays an N+1, recorded rather than fixed | Both available shapes cost more than the defect: batching needs an `IssuesController` hook WP2 has no other reason to open, and filling a whole tracker's cache re-introduces the system-wide scope read external F07 was raised to remove. `#tracker=` queries only when the tracker actually changes, so this is not the issue hot path. Finding G02, scheduled for WP6. |
| 2026-08-26 | WP3 | The summary page's grid stays a grid, and gets a project selector above it | Core's page answers "how many transitions has this workflow" for a grid of trackers and roles; the plugin's only change is *which* workflow, stated as a `project_id` predicate. Which projects deviate is a different question with a different shape, and it gets its own screen. |
| 2026-08-26 | WP3 | `#index` is rewritten rather than calling `super` and correcting the answer | Core's count is the defect: running it and discarding the result would still be a workflow query with no `project_id` predicate (INV-4, and the forbidden-constructs table). The two lines of core it duplicates are byte-identical in 5.1, 6.1 and 7.0. |
| 2026-08-26 | WP3 | With no plugin parameters, the count links keep core's URL byte for byte | `project_id[]=global` would be functionally identical but would put a plugin parameter into every link on an installation that does not use the plugin. |
| 2026-08-26 | WP3 | A multi-project selection on the summary page sums the selection's rules | It is the same population the matrix screens show for that selection, so the number in the cell is the number of rows the link opens. Per-project detail is the inventory's job. |
| 2026-08-26 | WP3 | The inventory counts the project's own rules, never the generic ones | An inheriting row therefore reads `0`, and the state label — not the number — says the generic workflow applies. Showing the generic count instead would put a number in the cell that does not match the matrix the cell links to. |
| 2026-08-26 | WP3 | The inventory is a route of the plugin's own, not a Deface override on a core screen | It has no core screen to attach to, and WP1's precedent (`/project_workflow_scopes`) keeps plugin paths off `/workflows`, where a plugin route drawn after core's could shadow one. |
| 2026-08-26 | WP3 | "Everything" mode addresses the product of projects, trackers and roles arithmetically | Materialising it would be projects × trackers × roles tuples in memory to show twenty-five of them. A page now costs the same on an installation with three projects and one with three thousand. |
| 2026-08-26 | WP3 | An inventory filter naming nothing that exists lists nothing, rather than everything | "No filter" and "a filter that survived nothing" have to be different answers, or a stale bookmark naming one deleted project answers with every project. |
| 2026-08-26 | WP3 | An unresolvable inventory filter value is a warning and a narrowed result, not a 404 | The filter is a form the operator can correct. The 404 in `ProjectWorkflowScopesController` is for links the screen generated itself, which is a different situation, and WP0 already set the precedent for form input on the copy screen. |
| 2026-08-26 | WP3 | The index header is one `surround` override rather than two inserts | Redmine floats `.contextual` and core always renders it before the heading, while the selector belongs under it. A surround puts both in one override with one anchor, and Deface raises if `<%= render_original %>` goes missing. |
| 2026-08-26 | WP3 | The project-selection helpers move out of `WorkflowsControllerPatch` into their own module | The patch is a set of replaced core actions; how a request names projects is the vocabulary they share. The split was forced by RuboCop's module-length limit and is the cut that reads best. Every method in it is private, because the module is mixed into a controller and a public instance method there is an action. |
| 2026-08-26 | WP3 | Five specs that create an `Issue` now declare the `enumerations` fixture themselves | The deleted characterization file was the only one loading it, and they had been passing on its side effect. Found by deleting it, which is the second time in this project that a spec turned out to be passing for a reason it never stated. |
| 2026-08-26 | WP4 | The project screen edits one tracker and one role at a time | The administration matrix edits a whole selection and needs a third "no change" state in every cell for it. Here the settings tab is the list and each line opens its own matrix, so every cell is a plain yes or no. Bulk editing across combinations is WP5's subject anyway. |
| 2026-08-26 | WP4 | The tab entry's `action` is the controller action it leads to, not a permission name | Two permissions reach the screen, and somebody who may *manage* the workflow must see the tab without also holding the permission to *view* it. Redmine's `allowed_to?` accepts either shape, and asking it about the action asks exactly what the controller will ask. |
| 2026-08-26 | WP4 | Both permissions also map `projects#settings` | That is the action the tab is rendered from, so without it a role holding only these permissions could not open the page the tab lives on. Redmine's own `manage_categories` is declared the same way. |
| 2026-08-26 | WP4 | Saving a project matrix while the project inherits is refused, not accepted | `TransitionWriter` and `PermissionWriter` create the scope a project write implies, so accepting it would turn "save" into "enable" — and the screen never offered an editable grid, because a project that inherits sees the generic workflow read-only. The three actions of INV-3 stay the only way to take a workflow over. |
| 2026-08-26 | WP4 | The project screen offers only the roles that have members in the project | Follows `docs/design.md`. The consequence is that the builtin roles — Non member and Anonymous — are not offered there and go on inheriting the generic workflow; a system administrator can still give a project its own workflow for them from the administration screens. Logged as an open choice below. |
| 2026-08-26 | WP4 | A project that inherits sees the generic workflow read-only, as disabled checkboxes | It is exactly what applies to that project until it takes over (INV-5), and a disabled checkbox is how core already draws a cell that cannot be changed. The editable case renders core's own `workflows/_form` partial unchanged, so the project matrix cannot drift from the administration one. |
| 2026-08-26 | WP4 | The tab's rows come from a helper, and the plugin patches no method of `ProjectsController` at all | First built as a patch on `ProjectsController#settings`. Superseded on the same day: once the tab override moved to the controller's *helper* chain (see "Where the settings tab attaches"), a second seam inside that controller bought nothing and carried the same alias-chain risk. `ProjectWorkflowsHelper#project_workflow_settings_rows` memoises `InventoryQuery` over one project — four collection queries, never one per row — and the failed-save path needs no special handling because a helper runs whenever the view does. |
| 2026-08-26 | WP4 | A scope action carries a `back_url` from the tab and none from a matrix | So an action taken on the tab comes back to the tab and one taken on a matrix stays on that matrix. Redmine's `redirect_back_or_default` validates the value, so a crafted one falls back to the matrix. |
| 2026-08-26 | WP4 | `spec/models/project_statuses_spec.rb` now declares the `projects_trackers` fixture, and its scoped-roles example moved to a leaf project | It was passing on whatever the previous spec file had left in that table, and its assertion — that the generic status is *absent* — is only true for a project with no descendants, because a scope on a parent says nothing about its children (INV-6). The third spec in this project found to be passing for a reason it never stated. |
| 2026-08-26 | WP4 | Locale parity is a spec now, not a hand check | `spec/locales_spec.rb` asserts that all eight files parse and carry exactly the same keys. It was checked by hand at the end of every session until now, which is precisely the kind of gate that eventually gets skipped. |
| 2026-08-26 | WP4 | The forbidden-constructs table in `CLAUDE.md` gains a row for a module `include`d into a controller | Every public instance method of a controller is an action, so such a module makes its methods routable and unauthorized. It has come up twice now — `WorkflowsControllerProjectSelection` in WP3, and `ProjectWorkflowsHelper` in WP4, where the fix was `helper` rather than `include`. |
| 2026-08-26 | WP4 | The tab override lands in `ProjectsController._helpers`, and the specs assert both halves | The behavioural half is a neighbour alias chain in miniature, in both load orders; the one that aliases *after* this plugin has applied is the one that fails, with the real error — `super: no superclass method 'project_settings_tabs'` — the moment the override goes back inside `ProjectsHelper`. The structural half asserts the arrangement itself, so a refactor fails in the suite rather than on somebody's settings page. |
| 2026-08-26 | WP4 | The narrowing this accepts is stated rather than left implicit | The tab now reaches `projects/settings` through `ProjectsController` only. A plugin rendering that view from a controller of its own would not see it — and would not see core's own tabs either, since the view reads `@project` straight from `ProjectsController`. |
| 2026-08-26 | WP5 | Core's check-all toggle is left exactly as it was, and the plugin adds three actions of its own | The premise of finding F06 — that the same classes on a mixed cell would make core's toggles reach it — turns out to be half the answer. The classes are needed and are now there, but core's selector is `input[type=checkbox]:not(:disabled).new-status-N`, and nothing that shape can ever match a `<select>`. Rewriting core's toggle to select on the class alone would also have to define "toggle" for a three-valued control, which is exactly the question the explicit actions answer. |
| 2026-08-26 | WP5 | The row and column actions are links calling one function, not a select that applies on `change` | A select acting on its own `change` event fires once per step when a keyboard user arrows through it, so it would apply values nobody asked for and prompt for confirmation on the way past. That is a known accessibility trap, and this repository has no way to test JavaScript, so the version with no event subtleties is the one to ship. Cost: three tab stops per row and column instead of one. |
| 2026-08-26 | WP5 | Two Deface overrides on core's `workflows/_form`, anchored on the header *cells* | The toggle expression itself is not usable as an anchor: 5.1 writes it as a bare `link_to_function` and 6.0 and later as `toggle_checkboxes_link`. The two cells are identical on all three, and anchoring on the cell puts the actions after the status name. The count goes from eleven overrides in ten files to thirteen in eleven, in `CLAUDE.md`, `docs/design.md` and the spec's comment. |
| 2026-08-26 | WP5 | The function is emitted once from the first row or column header, not from an anchor of its own | The transitions page renders the same grid three times, so a per-grid script would be written three times; an anchor carrying nothing but a script would be a fourth thing to go stale (INV-9). |
| 2026-08-26 | WP5 | "No change" is offered only where a cell can hold it | With one workflow per cell — every project matrix, and an administration selection of one tracker and one role — there is nothing to disagree, so the option would name a state the matrix cannot be in. |
| 2026-08-26 | WP5 | Core's `label_no_change_option` is reused rather than a clearer label of the plugin's own | The option in the cell and the action on the row would otherwise read differently for the same thing, in eight languages, and core's label is already translated everywhere. The clearer wording is a legend above the matrix instead, which is what the work package asked for. |
| 2026-08-26 | WP5 | `workflow_permissions_matrix_size` becomes a one-line delegation to `BulkActionsHelper#project_workflow_selection_size` | The cell helpers and the actions on a cell must not be able to disagree about whether it is mixed. Behaviour is unchanged for every case the old expression covered, and it now answers rather than raising when a view set neither list. |
| 2026-08-26 | WP5 | The selection note is rendered from the scope panel's anchor, and does not wait for a project to be selected | It belongs directly above the matrix, which is where the panel already is, so it needs no anchor of its own. Unlike the panel it shows for a generic-only selection of several trackers or roles, because that is a selection core's own no-change cells appear in — the first deliberate change to what an administrator who does not use the plugin sees, along with the actions themselves. |
| 2026-08-26 | WP5 | The confirmation threshold is a plugin setting, defaulting to 50 workflow rules | "Many" depends on the installation. 0 means ask every time. The browser counts only the controls whose value would actually change, so an action that changes nothing never asks. |
| 2026-08-26 | WP5 | The threshold's default is written down twice, with a spec asserting the two agree | `init.rb` declares it as the setting's default; `BulkActionsHelper` falls back to it for a settings hash an administrator saved before the key existed. Removing the duplication would mean requiring the plugin's lib before `Redmine::Plugin.register`, which reorders init.rb for a constant. |
| 2026-08-26 | WP5 | The settings screen has a spec of its own | A partial Redmine cannot find raises on the administration page and a field name that does not match what core writes back saves nothing while looking as though it did; neither is visible from any other spec. It also asserts the screen is administrator-only, because the plugin is what created it. |
| 2026-08-26 | WP5 | The legend is two sentences, and only the first goes on the field-permissions page | That page renders core's own no-change cells, so what a mixed cell means belongs there; the row and column actions do not exist on it, so explaining them there would describe a control that is not on the page. |
| 2026-08-26 | WP8 | The status-description icon on the issue form is **not** rebuilt — core already has it | `issues/_attributes.html.erb` renders an `icon-help` link and an `#issue_statuses_description` modal on 5.1, 6.1 and 7.0, listing `@allowed_statuses` with `IssueStatus#description`. That list is `Issue#new_statuses_allowed_to`, which this plugin replaces, so it is already the project's own effective workflow. WP8 adds specs (INV-4: it must never name another project's status) and a README paragraph, not a second icon for the same job. |
| 2026-08-26 | WP8 | The transition map is the plugin's own icon and modal, beside core's, not an extension of core's | Core's modal renders only when at least one available status has a description filled in, so extending it would make the map disappear on an installation that has never used that field. |
| 2026-08-26 | WP8 | The map's content is loaded lazily, into core's `#ajax-modal` | Rendering it inline would put a transitions query on every issue form, new and edit, for a panel most visitors never open (G6). |
| 2026-08-26 | WP8 | The map shows the workflow, and says so; the status dropdown stays the authority | `new_statuses_allowed_to` also drops closed statuses for a blocked issue or one with open subtasks, open ones for a subtask of a closed parent, and filters the author and assignee variants by identity. An edge the map draws and the dropdown withholds carries the reason — core's own `transition_warning` sentence where core has one. A map that silently disagrees with the dropdown earns a support ticket per edge. |
| 2026-08-26 | WP8 | The map is drawn for the user's **own** roles in that project | Those are exactly the roles the dropdown reflects, and explaining the dropdown is the whole purpose. A whole-installation view of every role already exists, on the administration screens and in the inventory. |
| 2026-08-26 | WP8 | Out of scope: the bulk-edit form, the issue show page, and editing a description from the map | A bulk selection spans projects and trackers, so one map would be a lie about most of it. The show page is worth doing and is a scope of its own — its reader may have no permission to change anything. |
| 2026-08-26 | WP6 | The audit trail keeps `created_*` and `updated_*` apart, and a repeated save moves only the second | They answer different questions: who decided this project runs its own workflow, and who last changed the rules. This is why `ensure_scopes` calls `touch_scopes` *before* it creates anything -- otherwise a row inserted by that call is stamped a second time with an `updated_at` later than its own `created_at`. |
| 2026-08-26 | WP6 | A save stamps every combination in its selection, not only the ones whose rules end up different | A matrix save submits and rewrites the whole matrix, so "saved by this person" is true of all of them. Telling a rewrite that changed nothing from one that did would mean diffing every cell on a path that already writes the lot. |
| 2026-08-26 | WP6 | The audit sentence is core's `authoring` with `label_updated_time_by`, not a string of the plugin's own | Already translated in every language Redmine ships, and it reads the way "Updated by X 3 days ago" reads everywhere else. Nothing is rendered where the scope has a time and no author -- the WP1 backfill's rows -- because "Updated by Anonymous" would name somebody who was not there. |
| 2026-08-26 | WP6 | The comparison compares core's three grids, not the stored rows | `WorkflowsController#edit` partitions transitions with `reject { author \|\| assignee }`, `select(&:author)` and `select(&:assignee)`, so a row with both flags set is in two grids at once. Comparing by grid is what makes the answer match what the screen shows rather than what the table holds. |
| 2026-08-26 | WP6 | The comparison is its own screen, not a third tab on the matrix | The two tabs there are the two kinds of rule and this is a view of one of them, so a third tab would leave one of the two showing as selected while the visitor is somewhere else. |
| 2026-08-26 | WP6 | A combination the project inherits says there is nothing to compare | Its workflow *is* the generic one. It also keeps a pre-WP1 database honest: rows stored against a project with no scope apply to nothing (INV-3), so listing them as differences would name rules that are not in force. |
| 2026-08-26 | WP6 | The comparison's ordering is computed in Ruby, never taken from the query | CI runs PostgreSQL, MySQL and MariaDB with a random rspec seed. An order that falls out of a query is not an order. |
| 2026-08-26 | WP6 | The inventory's comparison link leads into a project screen and may be refused there | **Corrected the same day, by the WP6 review:** this row first said "404" and named only the module and the tracker. It is **403** for a disabled issue-tracking module and for an archived project (`authorize` → `deny_access`) and **404** for a tracker the project no longer has *or a role whose last member has gone* (`find_tracker_and_role`). Either way the combination still has a scope and the project no longer offers the matrix to compare it against, so a refusal is the honest answer. Rendering the link conditionally would mean preloading each row's modules, trackers and member roles to answer a question the link itself answers. `docs/design.md` carries the table. |
| 2026-08-26 | WP6 | A field-permissions difference carries each side's rules as a **list**, and the copy screen stamps the audit columns | Both from the WP6 review. Two rows for the same (status, field) that disagree are possible; picking one would make the page depend on the order the database returned them, so the same install would compare differently on PostgreSQL and on MySQL — and core does not pick either. And a copy into a project that already has a scope rewrites its rules while creating nothing, so `ensure_scopes_for_copy` now touches as well as creates. |
| 2026-08-26 | WP6 | A difference naming a field the tracker no longer offers gets a footnote rather than being hidden | The rule is in the table and is a real difference; there is simply no control on any project screen that can change it. Considered and rejected: dropping such a line (it would make the page disagree with the database) and offering an action to delete the rule (a project screen writing rules for a field the project cannot see). |
| 2026-08-26 | WP6 | The undo is a stack, and it restores the value held *before* the action | Not the value the page was opened with -- those are the same thing only for the first action, and "no change" already means the latter. Repeated actions therefore step back one at a time. |
| 2026-08-26 | WP6 | The undo region stays visible once anything has happened; the undo *link* is what comes and goes | The last undo's own confirmation is the sentence the reader most needs, and hiding the region to signal an empty stack would take it away with them. |
| 2026-08-26 | WP6 | Every action of `ProjectWorkflowsController` is asserted to be named by a permission | Adding `compare` without touching `init.rb` produced a 403 for everybody, administrators included, and no "unmapped action" error anywhere. A structural assertion cannot go stale the way a list of action names would. |
| 2026-08-26 | WP6 | Finding G02 stays open, with WP2's reasoning confirmed rather than overturned | The request cache keyed by (project, tracker) is the narrowest key that can be correct; a per-`Tracker` memo is the project-blind cache INV-4 forbids. Collapsing the repeats across projects would put a query on every single-issue save to save one on a bulk move. |
| 2026-08-26 | WP7 | The release is **0.1.0**, and the CHANGELOG is reordered newest-first | 0.0.3 → 0.1.0 rather than 0.0.4: a new table, a migration with a backfill, two new permissions, three new screens and a changed answer to "does this project override" is not a patch release. Newest-first is what every other changelog does and what a reader checking "what changed since I installed it" needs. |
| 2026-08-26 | WP7 | The terminology bullet needed no work, and the plan says so rather than claiming it | *Generic workflow*, *Own workflow*, *Inherits the generic workflow* are what WP3, WP4 and WP5 used as they went. Same for "version-conditional code in one helper": `VersionHelper` already owns all five differences. A work package that reports work it did not do is worse than one that reports less. |
| 2026-08-26 | WP7 | `.rubocop_todo.yml` is annotated by hand, and anything added to it needs a reason | A generated list says which cop is off in which file and nothing about whether that is debt or a decision, and this one is almost entirely decisions — core's own method bodies, and `insert_all` in the writers, which INV-2 requires. 198 offences in 21 files became 50 in 8; the file's header names the three groups the rest fall into. |
| 2026-08-26 | WP7 | `TransitionWriter.transition_row` takes keyword arguments | The one `Metrics/ParameterLists` offence worth fixing rather than excluding: seven positional parameters ending in two booleans, so `transition_row(a, b, c, d, e, false, false)` put the author and assignee flags in an order nothing at the call site named, and swapping them writes a workflow permitting the opposite of what was asked for. |
| 2026-08-26 | WP8 | The panel gets a **controller of its own**, with no permission of its own | It reveals the workflow governing an issue the reader is already looking at, so `Issue.visible` (or, on the new-issue form, the project plus `add_issues`) is the whole authorization. Every action on `ProjectWorkflowsController` is behind `view_project_workflow`, and requiring that to read the workflow governing your own issue would hide the panel from the people it is for. `spec/controllers/project_workflow_maps_controller_spec.rb` asserts the action count, so a second action there cannot be added without a decision about how it is authorized. |
| 2026-08-26 | WP8 | The link carries the form's **tracker**, and the controller applies it to the issue before drawing the map | Core re-renders the whole issue form on a tracker change, so the link is rebuilt with it. Applying it is the same reconciliation `Issue#new_statuses_allowed_to` performs to pick its initial status — keep the status where the new tracker's own workflow uses it, otherwise that tracker's default — which is what makes the map and the status list read from one object rather than two. Considered and rejected: describing the issue as saved (the panel would then contradict the very dropdown it is beside), and duplicating core's private initial-status logic in the service. |
| 2026-08-26 | WP8 | A move's condition is worded *"only when the user is the author"*, in three keys of its own | Not the comparison screen's `label_project_workflow_condition_author` (*"also when the user is the author"*). There the label names one of core's three whole grids, which is core's framing; here the conditions of a single move have been collapsed, so a move naming only the author grid is a move **only** the author may make and "also" says the opposite of the truth. Both grids at once is one phrase rather than two joined by a comma, because "only the author" beside "only the assignee" reads as a contradiction. The unconditional case keeps the shared key, because there it means the same thing on both screens. |
| 2026-08-26 | WP8 | **Two** Deface overrides on `issues/_attributes`, not one | Caught by a probe, not by reasoning: core renders the status control two ways, and the second — a plain label instead of a select — is exactly what an own **empty** workflow produces, because `new_statuses_allowed_to` appends the issue's own status only when the workflow permitted something. A single anchor on `f.select :status_id` therefore withheld the panel in the one case the panel exists for. INV-9 count 13 → 15. |
| 2026-08-26 | WP8 | An **incoming** edge carries no availability | It ends at the status the issue is already in, so it is history rather than an action, and asking would answer "yes" for every one of them — the status list always offers the current status back. |
| 2026-08-26 | WP8 | `TransitionMapQuery` takes **no** `tracker:` argument | Raised by the fresh-subagent review as a latent contract hole, and the fix went the other way from the one suggested. The query took a tracker, queried the edges for it, and still read the status and the status list off the issue -- consistent only because the controller had applied the form's tracker first. Handing it a tracker the issue was not carrying produced a map whose edges and whose "offered now" column described two different trackers, which is the exact contradiction the class exists to prevent; the reviewer demonstrated it. Moving the assignment *into* the query would have fixed it too, but a query object that mutates its argument is worse: reading everything from the one issue makes the contradiction unrepresentable instead of merely unlikely. |
| 2026-08-26 | WP8 | A row naming a **deleted** status sorts last, not first | `position_of` returned -1 for any nil status record, which is right for core's "new issue" node and wrong for a row whose status has been removed -- it sorted ahead of every real status. Told apart by the **id** now (0 is the node), not by being nil. |
| 2026-08-26 | Review (codex F01, F02) | The copy screen's four "which workflow" selectors are validated by **one** guard, before anything is written | Source tracker, source role, target trackers and target roles were the four selectors the target *projects* rule had never been applied to, and the two findings are the same defect read from two ends: core cannot tell "any" from "the record is gone", and cannot tell "one of these ids is gone" from "here is what survived". Every write on that screen deletes the target pair's rules first, so the guard runs before the branch that writes rather than inside it. |
| 2026-08-26 | Review (codex F01) | The guard runs for **every** copy request, not only for one that names a project | The finding places the defect in the plugin's project branch, but the copy form's target project selector is a `multiple` select, and one with nothing selected submits nothing at all — so the request goes to core, unguarded, from the plugin's own form. Checking before the delegation costs one repeated `find_sources_and_targets` on a screen an administrator uses a handful of times a year. |
| 2026-08-26 | Review (codex F01) | The shape of a source id is checked as well as the record it names | Core resolves the id with `to_i`, so `'12abc'` silently means tracker 12 — the same reason `validated_target_project_ids` has required `\A\d+\z` since WP0. |
| 2026-08-26 | Review (codex F01) | An unresolvable source tracker or role is reported with core's `error_workflow_copy_source` | The plugin's own `error_workflow_copy_source_project` ("Please select a source tracker, role, and project") is the message for the *project* half of the source. Core's key names what is actually wrong, is already translated in every language Redmine ships, and leaves the two causes distinguishable on the screen. |
| 2026-08-26 | Review (codex F02) | A target tracker or role that does not exist gets a key of its own, `error_workflow_copy_target_tracker_or_role` | Parallel to `error_workflow_copy_target_project`, and deliberately not merged with `error_workflow_copy_target`: "you selected nothing" and "what you selected is gone" send the administrator to look at different things. Added and translated in all eight locale files, per the locales rule. |

## Open — for Jan

- **Choice (finding F01, 2026-08-27-bundled-followup):** when a matrix save
  refuses some of the values it was sent, the screen says *"N submitted values
  were not accepted and the rules they name were left unchanged."* On the
  administration screens a selection is written one population at a time
  (*Generic*, then each selected project), and the same refused value was counted
  once per population — so one bad value on an "all projects" save of a
  five-hundred-project installation claimed five hundred. What should the number
  mean?
  - **A — one count per submission.** The number is how many values the request
    carried that were not accepted, whatever the selection was resolved into.
    The sentence stays exactly as it is in all eight locale files. **Implemented,
    as the safest reversible default:** `MatrixSaveResult#+` now takes the
    maximum of `rejected` instead of adding it, and two spec assertions that had
    encoded the multiplied number were corrected.
  - **B — keep the total and reword the sentence** to name refusals across the
    selection rather than submitted values, e.g. *"N refusals across the
    selection"*. Cheaper in code — nothing changes — and more expensive in words:
    a new phrasing in **eight** locale files, of which `de`, `es`, `fr`, `it`,
    `pl` and `pt` would be unreviewed translation presented as translation. It
    also asks the operator to care how many populations a selection resolved
    into, which is an implementation detail of the save rather than something
    they chose.
  - **Recommendation:** **A**, which is what is in place. The operator submitted
    one value; being told one value was refused is the answer to the question
    they can actually ask. B is the right answer only if you would rather the
    number stayed a total for auditing, and if so it is a locale change plus
    reverting one line.
  - **Urgent?** no — A ships, and it is one line and two assertions to reverse.
    Reachable only through a hand-built request or an API client either way: no
    screen can submit a value the whitelist refuses.

*(Everything else here is answered. Items land here with their options, a plain-language explanation
of each and a recommendation, while the build continues on the safest default.
Everything ever filed here has been answered, and **G02 on the day it was
filed** — 2026-08-27, `A for now, B if it becomes an issue later`. Before it: the
two of that same day, the review loop's branch (**F09**) and whether the
`.codex/` scripts should come back (**F08**), answered **A and A**, as was the
bulk scope-create question; finding **C01** was answered **B** on 2026-08-26, as
were WP8's two (**A**), WP7's one, WP8's renderer choice (**C**), WP4's two and
WP5's one.)*

## Decided (autonomous) — 2026-08-26, review-fix session

- **A matrix save never creates a scope, on any screen.** The administration
  matrices used to; the project's own tab has refused since WP4. Class B (it
  changes what an administrator sees), decided rather than deferred because the
  old behaviour could hand a project an own *empty* workflow from a Save nobody
  had touched, which ADR-001 names as the state to keep unreachable by accident.
  Reversible: `TransitionWriter.writable_pairs` / `PermissionWriter.writable_pairs`
  are the whole of it. Options considered — (A) refuse, and say how many
  combinations were left alone; (B) keep enabling but ask for confirmation first;
  (C) render the generic workflow read-only for an inheriting selection, as the
  project screen does. **A** shipped: B still enables on one click-through and
  leaves two screens disagreeing about what Save means; C is a bigger change to
  core's own grid and does not answer a *mixed* selection, where some
  combinations inherit and others do not. Half of C shipped anyway as a sentence:
  the panel says the empty-looking combinations are the inheriting ones.
- **The transitions writer deletes per rule, not per cell.** Not a choice so much
  as core's own semantics restored; recorded because the delete/insert shape is
  what makes the writer fast and it now carries one extra SELECT for the cells
  whose author or assignee column was submitted.
- **`ScopeWriter` creates scopes with `insert_all`.** The forbidden-constructs
  table bans `insert_all` outside the two rule writers because it skips
  validation (INV-2). Nothing here comes from a request: the ids are resolved
  from the database and the rule type is checked against `RULE_TYPES` by a guard
  that replaces the model's `validates_inclusion_of`. Same argument `ScopeCopier`
  already makes for its raw `INSERT ... SELECT`.
- **Two duplicate-flag rows are merged with OR, not by picking one.** When the
  table holds two author/assignee rows for one cell — which no constraint
  prevents — the writer now reads them to preserve a flag left at *(No change)*.
  Picking one would depend on the order the database returned them and would
  differ between PostgreSQL and MySQL; OR is deterministic and is what the matrix
  already renders, since it draws a checked box for either flag.
- **`issue_statuses/index`'s project-blind query is left alone.** Documented in
  `docs/design.md` instead. It drives a badge, not a gate, and correcting it
  would cost a sixteenth Deface override.
- **The project selector goes on listing every project.** Recorded as a cost in
  `docs/design.md`. Narrowing it would mean deciding which projects an
  administrator may not configure.

## Decided (Jan) — 2026-08-26

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-26 | What the first of the three states is called, on screen | "Follows the generic workflow", not "Inherits…" | Jan raised it himself, having read the plugin's own screens and asked what workflow inheritance was — Redmine has none, and the word suggested a project tree that INV-6 explicitly rules out. Changed in all eight locale files, for the label, the mixed-selection count, the two read-only sentences, the refused-save notice, the panel note and the comparison sentence. The **internal** vocabulary is deliberately unchanged: the state symbol is still `:inherits`, so are the locale key names, `ScopeWriter.return_to_inheritance`, the `project-workflow-scope-state inherits` CSS class a theme may already target, and INV-6's wording. Renaming those is churn with nothing visible behind it, and the CSS class is somebody's hook. A later session should not "fix" the difference between the two by reverting the strings. |

## Decided (autonomous) — 2026-08-27, review-fix session

- **Scope creation goes back to one validated `save!` per combination.** The
  forbidden-constructs table in `CLAUDE.md` bans `insert_all` outside the two
  rule writers, and 0.1.1's entry above argued its way around it. Class A, not
  a judgement call: the table is a gate (G7), a decision log does not lift one,
  and the argument was wrong on its own terms as well — `insert_all` skips
  conflicting rows rather than raising on them, so a scope somebody else had
  just created was reported as created here too. The entry above stands as a
  record of what was decided then; this is what is true now. Whether a bulk
  boundary *should* exist was put to Jan the same day and answered **A**: it
  should not. See "Decided (Jan) — 2026-08-27" below.
- **`enable` acts on what it created, not on what it meant to create.**
  `ScopeWriter.create_scopes` returns the combinations whose row it actually
  inserted, and the clearing and copying of rules follows that list. Two
  administrators pressing the button together no longer means the second one
  overwrites the first one's freshly copied rules.
- **A rule write locks the scope rows it depends on.** `writable_pairs` takes
  `SELECT ... FOR UPDATE` on the exact scope rows, inside the transaction that
  then writes the rules, and *return to the generic workflow* and *empty the
  matrix* take the same locks first. Class A — it is the ordinary fix for a
  check-then-act race, it is invisible when nothing is concurrent, and the
  alternative was leaving rules in the table that no resolver would ever read.
  The lock is taken by primary key, in id order, in a second statement: by
  primary key because InnoDB would otherwise gap-lock a mostly empty range, in
  id order because two callers must take the same locks in the same order, and
  in a second statement because what it returns — not what the first statement
  found — is the answer.

## Decided (Jan) — 2026-08-27

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-27 | Whether creating scopes in bulk may use one statement for many rows | **A — leave it.** One validated insert per combination; no bulk boundary, no ADR | Asked because restoring the forbidden-constructs rule (F01 of the 2026-08-27 review) costs *give own workflow* one round trip per (project, tracker, role) where 0.1.1 made one per thousand. **A** was the recommendation and is now the decision, so the shape in `ScopeWriter.create_scopes` is the intended one rather than a default awaiting review: one `ProjectWorkflowScope#save!` per combination, validations and all. Considered and rejected: **B**, an ADR permitting a bulk scope create in `ScopeWriter` only — faster, and it would have made the rule mean what the code does, but it widens a gate that exists precisely because it is narrow; and **C**, chunking or backgrounding the action, which is a bigger change and a new moving part for a cost nobody has reported. What this closes off, so that a later session does not re-open it as an optimisation: the round trips in `create_scopes` are **not** a performance defect to be fixed with `insert_all`. If the slow case is ever actually met, it is B that gets re-opened — with an ADR — not the code. |
| 2026-08-27 | Whether the review loop goes on telling a reviewer to review the head of `main` | **A — change the sentence.** A reviewer reviews `claude/dev`; `main` stays where it is and means "last released" | Finding **F09**, left at `question` by the fixer because it was not a fixer's to settle. `main` was three commits from before 0.1.0 while `claude/dev` carried eight work packages and three review rounds more, so a reviewer following the old instruction would have spent a session on code that no longer exists — and the findings-file format records the commit without checking it against the branch. `docs/review/README.md`'s Branches table and `docs/review/PROMPT.md`'s checkout block both changed; three further corrections went in with the sentence, because each was a way the loop could still mislead: the cycle diagram now says that a fixer answers a findings file on `claude/dev`, **so `main`'s copy keeps the original statuses** (the `G03` shape, stated out loud at last); both files record that `main` and `claude/dev` share **no merge base**, so the eventual merge needs `--allow-unrelated-histories` and a reviewer must not attempt it to make the old sentence true; and `PROMPT.md` uses `git checkout -B claude/dev origin/claude/dev` rather than `pull --ff-only`, which aborts when a fresh container's local branch is itself unrelated to the remote. Considered and rejected for now: **B**, merging `claude/dev` into `main` — kept for when a release is due, which is what the recommendation said and what was chosen. |
| 2026-08-27 | Whether the three deleted `.codex/` setup scripts should come back | **A — leave them deleted.** `dev/` is the only supported path and `dev/README.md` says so | Finding **F08**. Nothing in the repository, in CI or in any document referred to them; `redmine_clone.sh` named `5.1-stable, 6.0-stable, 6.1-stable` as the supported set, which is neither the current one nor a subset of it; and its `rsync -a --delete --exclude "$REDMINE_DIR/"` did not exclude `.redmine/`, so running it from a working checkout would have copied every built host into the plugin directory. Both Codex sessions that reviewed this repository that week had no host at all, so nothing was using them. Considered and rejected: **B**, restoring and maintaining them — that means carrying a second, differently shaped setup path for a harness nobody was running it from. `git log -- .codex` recovers them if that changes. |
| 2026-08-27 | Whether scope changes should carry an append-only event log recording *what* changed and through which action | **A — leave it.** `created_by` and `updated_by` remain the whole audit story: no event log, no table, no ADR-002 | Finding **F21** of `2026-08-27-bundled`, filed as a `question` by the reviewer and never a fixer's to settle. Asked because Redmine does not audit generic workflow changes either — so this is parity — but Redmine also does not delegate workflow editing to project members, and this plugin has since WP4, which makes "who removed this transition" a question a project manager can now cause and nobody can answer. **A** was the recommendation and is now the decision. Considered and rejected: **B**, an append-only event log — it needs a table, a retention policy, a rule for what happens when a project is deleted and a position on what may be stored, which is an ADR rather than a patch. What this closes off: a later session must not add an event-log table on the grounds that the audit trail is thin. It is thin **on purpose**. What it does *not* close off, because F19 landed in the same session and changes the picture without answering the question: every workflow write now logs one line — action, rule type, actor id, project/tracker/role ids, and the counts written, skipped and refused. That is an *operational* record, not an audit trail: not queryable, not retained on a policy, not attached to the project, and it goes wherever the host sends its log. So "what did that request do" is answerable to somebody with log access; "who removed this transition, and when" is not, and that is now a decision rather than an omission. If Jan is ever actually asked the second question, B is what gets re-opened — with an ADR — not this row. |

## Decided (autonomous) — 2026-08-27, second review-fix session

Eight findings of the independent review of `c3047cf`. Class A unless said
otherwise.

- **'All' is carried into the Save as 'all'.** The two hidden-field Deface
  overrides expanded it into every project id; the scope panel four files away
  has kept it verbatim since WP1, and there was a spec asserting so. Class A —
  the repository already held the rule, in one of two places (finding F01).
- **The rule writers report what they wrote, not only what they refused.** A new
  `MatrixSaveResult` with `written` and `skipped`, summed across the projects of
  a selection, replaces the bare `skipped` count, and the
  `(projects × trackers × roles) − skipped` arithmetic is gone from the
  controller. Class A: two counts cannot be recovered from one, and the
  subtraction is what made a rejected payload read as a full save (finding F06).
- **A matrix save that applied nothing says so, on both screens.** Class B, and
  decided rather than deferred. Core reports *Successful update* for a save where
  every cell was left at "(No change)", and this now does not; the alternative —
  reporting nothing at all, which is what the finding literally asked for —
  leaves somebody pressing Save with no feedback, which is worse than either
  wrong message. One new key, `notice_project_workflow_save_nothing_applied`,
  whose sentence covers both causes: nothing was changed, or nothing submitted
  was accepted. Reversible: delete the key and the branch that sets it.
- **A copy reports the workflows it emptied rather than refusing to empty
  them.** Class B, and the finding's own cheaper option. A copy replaces, so a
  source with no rules of one kind leaves the target's scope of that kind
  standing and empty; refusing would break the one way somebody can deliberately
  empty a project. One new key,
  `notice_project_workflow_copy_left_empty`, pluralised (finding F03).
- **A copy stamps the audit columns of the combinations it copied, and no
  others.** `WorkflowRule.copy_for_project` returns the pairs it actually copied
  — it skips any whose source resolves to the target itself — and
  `ScopeWriter.touch_combinations` stamps exactly those triples.
  `touch_scopes`, which stamps the cross product of three id lists, stays for
  the matrix save, where the cross product genuinely is what was rewritten
  (finding F04).
- **A new service, `ScopeCombinations`, holds the questions a *set of exact
  triples* can be asked.** Class A, and forced twice: by F04, which was the
  cross product speaking for combinations nobody named, and by
  `Metrics/ClassLength`, which `ScopeWriter` crossed. Read-only; every query
  names its project ids (INV-4).
- **A project's Workflow tab lists a role that already has a scope, even with no
  member in the project — but is not offered a new workflow for it.** Class B,
  and deliberately the narrowest reading of Jan's answer **A** of 2026-08-26:
  that answer is about the *offer*, and it stands. `require_offered_role` answers
  403 for `#enable` alone; every other action acts on a scope that already
  exists. Reversible: `ProjectOptions.visible_roles` back to `.roles` (F05).
- **`.rubocop.yml` targets the oldest supported Rails, 6.1.** Class A: a lint
  gate configured for the newest host can approve a method the oldest cannot
  run, which is worse than no gate. Asserted from inside the suite, so the 5.1
  cell fails if it drifts upwards again (finding F02).
- **`duplicate` keeps its asymmetry with `copy` and explains it.** It never
  reads `params[:project_id]`, so 404 for a value there would report a fault
  that does not exist. A characterising example pins the choice (finding F07).
- **The `.codex/` scripts are deleted.** Class B, logged above under
  *Open — for Jan* (finding F08).

## Decided (autonomous) — 2026-08-27, review run `2026-08-27-bundled`

All Class A unless it says otherwise. Findings F01–F20 of
`docs/review/findings/2026-08-27-bundled.md`.

- **The copy screen takes the scope lock before it writes a rule.**
  `ScopeWriter.lock_scopes_for_copy`, first statement in `#duplicate`'s
  transaction, over the combinations `WorkflowRule.copy_pairs_for_project` says
  it is about to write. The lock names existing scope rows by primary key in
  ascending id order and filters no rule type, so it queues against the three
  callers of `lock_combinations` rather than deadlocking with them (F01).
- **The copy still creates scopes where none exist, rather than filtering its
  targets by the locked answer.** With the lock held first, every commit order
  ends consistently; filtering would make a legitimate creation depend on a
  race. The residual copy-versus-`enable` cycle on a combination with **no**
  scope row is recorded rather than chased — the unique index serialises it and
  no row lock can close it; if it is ever observed the answer is a
  `rescue ActiveRecord::Deadlocked` on the action, not a wider lock (F01).
- **A lock-order claim in `docs/design.md` names its paths and its exception.**
  The old sentence was a universal recorded from a sample of three, which is how
  the copy path came to be skipped. It now says four paths, names the copy, and
  states that the order holds *for combinations that have a scope row* (F02).
- **Upstream drift is detected, not declared, and `requires_redmine` stays a
  floor.** `spec/upstream/core_drift_spec.rb` digests core's own body for every
  method the plugin shadows — eighteen, discovered at runtime, private ones
  included — against a table measured per Redmine minor, and calls core as an
  oracle. Narrowing `requires_redmine` to a range was rejected: an out-of-range
  Redmine then refuses to boot until an administrator deletes the plugin
  directory, which trades an uncertain divergence for a certain outage. A
  Redmine minor the table has not measured is **reported, not failed**, for the
  same reason (F03).
- **The 5.1 floor is a hard dependency, and `init.rb` says so.**
  `Issue#roles_for_workflow` does not exist before 5.1 and `TransitionQuery`
  calls it, so lowering the floor ships a `NoMethodError` on every issue save
  rather than widening support (F03).
- **The administration matrices prepare nothing before authorization.** One
  guard clause inside the patched finder, not a second scoped `require_admin` —
  which would *delete* core's unconditional registration, because
  ActiveSupport's callback dedupe ignores `only:`. The guard prepares data and
  does not authorize; `require_admin` still decides (F05, F18).
- **INV-4 has exactly one named exception, and a gate keeps it at one.**
  `WorkflowRule.copy_one_with_projects`: both its statements span the generic
  and project populations because "duplicate this role including every
  project's workflow" is defined that way (F18).
- **The JavaScript gate is a CI job.** `Bulk action script`, beside `RuboCop`.
  Capybara and axe-core were rejected as disproportionate to 85 lines across
  nine host checkouts (F07).
- **The INV-9 override count is asserted, as a speed bump and described as
  one.** It cannot tell that a sixteenth override has an assertion; it makes
  adding one a deliberate act. Deface's own registry was not introspected, to
  avoid coupling the gate to that gem's internals (F08).
- **Focus moves to the undo region before the undo link is hidden.** Only when
  the stack has just emptied, the link was visible, and it holds focus — so
  focus is never taken from wherever the user actually is (F15).
- **`normalize_permissions_params` is deleted.** Fifteen lines transposing a
  payload shape nothing produces: `permissions[<status>][<field>]` is what core's
  helper and the plugin's own grid emit on 5.1, 6.1 and 7.0, checked in all three
  checkouts. It also silently discarded the real matrix for a mixed payload
  (F14).
- **The plugin's `Gemfile` names only `deface`.** Redmine evals
  `plugins/*/Gemfile` into the host's bundle, so the test gems were in every
  installation's production bundle; `dev/setup.sh` already writes them into
  `Gemfile.local`, which Redmine evals first. `deface` stays **unpinned**: there
  is no range (one release since 2022-04-01), a plugin fragment cannot protect a
  host that owns its own lockfile, and a constraint can import a neighbour's
  resolver conflict. `bundle-audit` as a gate was also rejected — it would fail
  on an unfixable EOL-Rails advisory and redden a third of the matrix (F12).
- **CI declares `permissions: contents: read`, and the Redmine matrix stays on
  moving branches.** No step uses the token, so capping it is free and broader
  than SHA-pinning the two actions. The `*-stable` branches are deliberately not
  pinned: they are the plugin's only free early warning that core changed, which
  is the F03 risk. One line now prints the tested Redmine commit in every cell,
  so a red cell is attributable (F13).
- **The copy screen's project labels are associated with their selects.**
  `for=` on both. Core's own four labels on that screen have the same problem;
  that is core's to fix (F16).
- **A save carrying no matrix at all says nothing was saved.** Class B, safest
  reversible default: it reuses `notice_project_workflow_save_nothing_applied`,
  already translated in all eight locales, so nothing touches i18n. The
  alternative — staying silent — is the defect the earlier F06 was about (F17).

- **Both timestamp writers build the value in Ruby, and migration 004 was
  changed to do so too.** `CURRENT_TIMESTAMP` is UTC only on PostgreSQL —
  `AbstractMysqlAdapter#configure_connection` sets no `time_zone` in Rails 6.1,
  7.2 or 8.0 — so on six of the nine supported cells the audit columns held the
  server's local time and Rails read it back as UTC. `connection.quoted_date`
  with the standard `TIMESTAMP '...'` type keyword, accepted by all three.
  Touching a *shipped* migration was the judgement call the finding left to the
  fixer: an installation that has already run 004 keeps what it wrote, so the fix
  reaches only future installations, and the divergence is harmless because a
  backfilled scope displays no time at all (the helper returns early when
  `updated_by` is blank). Fixing only `ScopeCopier` would have closed the live
  path while knowingly shipping the defect. The 2026-08-26 entry above is marked
  superseded rather than edited (F09).

## Decided (autonomous) — 2026-08-27, F11 session

Class A, and the last open finding of `docs/review/findings/2026-08-27-bundled.md`.

- **`StatusListQuery` emits one OR branch per override *configuration*, not per
  overriding pair.** The group key is (tracker, sorted role-id set) and each
  branch carries a `project_id` list, so every project that answers for the same
  roles for the same tracker — which is what copying a workflow to a subtree
  produces — shares one branch. The branch count is bounded by configuration
  variety rather than by project count, on the administration matrix with "all
  projects" selected *and* on `Project#rolled_up_statuses`, which fills the
  status filter and the status report on every project issue list. That second
  screen is why the growth was worth fixing rather than pricing in: it is a page
  view, not an admin action (F11).
- **The excluded generic roles stay an intersection across the whole pair set,
  and both methods now say that this is load-bearing.** A generic role is out of
  reach only when *every* pair for the tracker answers for it (INV-6), so it
  cannot be computed per group. Nor may the pairs be grouped by tracker alone
  with the role sets unioned: that reads a project against roles it does not
  answer for (INV-5), which an orphaned rule row makes visible (INV-3). Both
  wrong versions were implemented on purpose and each was confirmed to fail an
  example before being reverted (F11).
- **The tuple `IN (VALUES …)` rewrite stays rejected** — three spellings for
  three databases, and grouping is the larger win anyway. What is *not* claimed
  is that the growth is gone: the bind parameter list still carries one
  parameter per overriding project, so PostgreSQL's 65,535-parameter ceiling is
  raised rather than removed, and `docs/design.md` says so (F11).
- **The statement-shape examples count `project_id` predicates, not
  `tracker_id`.** Rails factors the predicates common to every branch out of an
  `OR`, so a `tracker_id` count is 1 whatever the branch count — the first
  draft's gate, which would have asserted nothing. This is the third time in two
  sessions that a shape assertion had to be measured before it could be trusted
  (F04, F10, F11).

## Decided (Jan) — 2026-08-28

Three answers, all taken as recommended, that set the shape of **WP9 — the
workflow as a drawing, per role**. The request behind them: an ex-Jira user reads
the missing diagram as Redmine falling short, so the answer has to be a drawing
that is genuinely more useful than Jira's rather than a catch-up.

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Where the full drawing lives | **A — the project screen, beside the matrix; the issue panel keeps the local "from here" view and gains a link** | Measured, not estimated: five layers of a six-status workflow are 1016 px wide and each further status adds about 210 px, while Redmine's `#ajax-modal` is about 900 px; scaling to fit puts the status names below legibility. Considered and rejected: **B**, the drawing in both places with horizontal scrolling in the modal — a scrollbar in a dialogue is not an answer to a question asked in a hurry. The split also matches the use: on an issue you want to know what you may do now, on the project screen you want to understand the whole thing. |
| 2026-08-28 | Who may see the full drawing | **A — behind `view_project_workflow`; the WP8 panel keeps no permission of its own** | The whole map shows what *other* roles may do, which is project configuration rather than information about the issue in front of you. The panel stays ungated for the reason WP8 gives: requiring a permission to learn which workflow governs your own issue would hide it from the people it exists for. Considered and rejected: **B**, the full drawing without the permission. |
| 2026-08-28 | Which roles the selector offers | **B — every role the project screen already lists, with the reader's own roles as the default union** | "What may a developer actually do here" is exactly the question of somebody administering the workflow, the permission that answers it already exists, and the screen is behind it — so restricting the selector to the reader's own roles would withhold something the reader is already entitled to see. Considered and rejected: **A**, own roles only. The population is `ProjectOptions.visible_roles`, the same one the settings tab and the matrix use: roles with members in the project plus any role that already holds a scope. **Not every role in the installation** — 2026-08-26 settled that the project screen offers only the roles the project has, and this answer does not touch it. The selector is omitted entirely when there is only one thing to pick. |

**What this does not do: it does not re-open 2026-08-26's answer of C.** C chose
the local view for WP8's panel and said in the same sentence that a layered
diagram is that same data with a layout pass added, so A stays buildable on top.
WP9 is that increment, on a different screen; the panel C describes is unchanged.
The rejected half of C — *no drawing anywhere* — was never what C said.

The technology question was asked with it and is recorded because the answer is
not the obvious one: **inline SVG with the layout computed in Ruby**. At this size
— as many nodes as the installation has issue statuses, usually six to fifteen —
the drawing technology does not affect speed at all; what matters is what reaches
the browser and when. SVG wins on everything around it: real text that is
selectable, findable and readable aloud, `currentColor` carrying whatever theme
is installed, and printing. Considered and rejected: **Canvas** (loses text,
accessibility, selection and print, and only wins above thousands of elements),
**Mermaid** (about a megabyte, its own theme and font, interaction per edge a
fight), **Graphviz as WebAssembly** (two to three megabytes for twelve nodes),
**dagre / ELK / Cytoscape** (an npm build step this plugin does not have and does
not want), and **Graphviz on the server as a PNG** (a system package many Redmine
administrators may not install, no interaction, no theme). Kept in reserve:
**HTML nodes over an SVG edge layer**, which would make status names wrap by
themselves — worth returning to if the wrapping in Ruby proves worse in practice
than it looks on paper.

## Decided (autonomous) — 2026-08-28, WP9 build session

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Version number for WP9 | **Bump to 0.1.6**, with a `CHANGELOG.md` entry of its own | The previous session deliberately did *not* bump for four small fixes, on the grounds that 0.1.5 has never been released (`main` carries 0.0.3, there is no tag) and a version whose only difference from an unrun one is four repairs is not worth minting. That argument does not carry to a whole feature: a reader scanning the changelog for "when did the diagram arrive" needs a heading to find, and the entry is a page long. `spec/plugin_conventions_spec.rb` asserts `init.rb` and the newest changelog heading agree, and both moved together. |
| 2026-08-28 | Where the graph's topology phases live | **A class of their own, `Services::WorkflowGraphRanking`** | `WorkflowGraphLayout` reached 356 code lines against a `Metrics/ClassLength` limit of 200 that `.rubocop.yml` has already relaxed once with a stated rationale — so crossing it is a signal to extract rather than a cop to placate (this repository has been here six times, and all six extractions were genuine improvements). The split is real rather than arithmetic: reachability, the cycle break, the layering and the ordering mention no pixel, and "the graph's shape" and "where things go on the page" are two things. `WorkflowGraphText` came out for the same reason and is the second half of it: "how a status name is shortened to fit a box" is a decision worth changing, and testing, without a graph. |
| 2026-08-28 | What an *own empty* workflow draws | **The entry node alone, with the sentence — not a band holding every status the tracker uses** | The query reports every status the project's effective workflow uses, including the ones only another role's rules name, so a literal rendering would draw one node and a band of thirty dashed boxes under "not used by the selected roles". That is true and useless: "every status is unmentioned" is *what an empty workflow means*, and thirty of them buries the one sentence that explains it. The diagnostics list is suppressed in the same case and for the same reason. Reversible by deleting one branch in `WorkflowGraphLayout#drawn_status_nodes` and one guard in `ProjectWorkflowGraphsHelper#project_workflow_graph_diagnostics`. |
| 2026-08-28 | Two different reasons for a drawing with no arrows | **Two sentences, keyed on the scope state and never on the absence of rules** | Found by the review role against this package's own first draft, and it is INV-3's defect in miniature: the view keyed its "this project has its own workflow here and it holds no rule at all" sentence on `edges.empty?`, which is *also* true of a project that inherits a generic workflow nobody has filled in — so the screen asserted a configuration the project had not made. `text_project_workflow_graph_nothing` is the second sentence; the first now fires on any role whose state is `own_empty`, whether or not another role's rules put arrows on the page. Two of the three regression examples are red against the first draft. |
| 2026-08-28 | Whether the band of unreachable statuses gets a caption inside the drawing | **No — a dotted rule inside the SVG, and the words immediately below it in HTML** | SVG neither wraps nor measures text, so a `<text>` caption on a narrow drawing (one unreachable status is 132 px wide) runs outside the `viewBox` and is clipped, silently, which is the same class of bug the `viewBox` spec exists for. The rule is unmistakable inside the picture and the sentence below it can wrap. Considered and rejected: reserving horizontal room in the layout for a string the layout cannot measure. |
| 2026-08-28 | How the drawing distinguishes anything | **Line style and words only; no literal colour anywhere** | The plan allowed "a literal hue only for the marks that carry meaning", and in the event nothing needed one: a move anyone with the role may make is a solid arrow and one only the author or assignee may make is dashed, a status outside the flow has a dashed outline, and the legend says which is which. Everything is `currentColor`, so a third-party theme recolours the drawing with the page — and the plugin ships no stylesheet, so a colour would have had to be an inline attribute no theme could reach. One `<marker>` serves every arrowhead as a consequence. |
