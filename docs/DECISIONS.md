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
| 2026-08-28 | The HTTP 500 Redmine's own workflow save answers to a malformed matrix (WP12) | **A — leave it** | `params[:transitions]` arriving as anything but a nested hash — `?transitions[]=x`, or `transitions=x` — reaches core's own `each_value` and raises `NoMethodError`. Measured on a 7.0 host, in both save actions and for both a String and an Array. Stock Redmine on a stock Redmine, and nothing reaches the database (INV-2 holds) — but the plugin's patch guarded that screen until WP12, so it is a change relative to the last release even though it is not a change relative to Redmine. No form produces such a request; an administrator hand-building a POST does. **A** is what ADR-003 already decided for these screens: Redmine's do exactly what Redmine does, and the plugin's own screens go on rejecting the same payload with a message, because those are screens the plugin owns. **B** — a two-line guard in `WorkflowsControllerPatch` — was rejected: it is a defect of core's, fixed on core's controller, by this plugin, on a screen this plugin is meant to have stopped editing, and every such line is one a Redmine upgrade can break. Nothing to implement; A was already in place. |

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

- **Choice (finding F01, 2026-08-28-claude-second):** Redmine's *Copy project*
  brought everything else across and left the project's own workflow behind, so
  the copy silently ran the generic workflow. Nothing anywhere said so — no ADR,
  no design note, no README line — so this was an unconsidered gap rather than a
  choice. Which should it be?
  - **A — copy the workflow.** A copied project runs the same workflow as the
    original: the decisions and the rules, an own *empty* workflow included, for
    the trackers the copy actually has. **Implemented, as the safest reversible
    default:** a `model_project_copy_before_save` listener and
    `Services::ProjectWorkflowCopier`. Reversible from the screen — one *Return
    to the generic workflow* per combination on the copy's own Workflow tab —
    and reversible in code by deleting one `require_relative` and one file.
  - **B — say it instead.** Leave the behaviour and write it down: a paragraph
    in the README and a line on the copy form saying a copy starts from the
    generic workflow. Cheaper, and it makes the surprise visible rather than
    removing it.
  - **Recommendation:** **A**, which is what is in place. The direction of the
    surprise decides it: a project is usually given its own workflow to be
    *stricter* than the generic one, so under B the copy comes out **more
    permissive** than the original and the first sign of it is somebody closing
    an issue that should not have been closeable. A also matches what
    duplicating a role or a tracker has done since 0.1.0, and what
    `Project.copy_from` already does with trackers, modules and custom fields —
    the workflow was the one piece of configuration left behind.
  - **What A costs:** a copy of a project with a large own workflow now writes
    those rules too (two INSERT … SELECT statements, no per-row round trip).
  - **Answered by Jan on 2026-08-28, the same day:** *"in Redmine when copying a
    project there is a checkbox to copy issues, wiki, and so on… should we not
    add a checkbox for project specific workflows?"* **Yes — A with a checkbox**,
    built the same day. The reason this entry originally gave for not having one
    was **wrong on a fact**: it said a checkbox means a Deface anchor on core's
    copy form (INV-9), and it does not. `app/views/projects/copy.html.erb`
    renders `call_hook :view_projects_copy_only_items, project:, f:` inside that
    very fieldset, on 5.1, 6.1 and 7.0 identically — an extension point core
    added for exactly this. The item is ticked by default, so A stays the
    default and the parameter can only ever narrow what is copied.
  - **Urgent?** no — answered and built.

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

## Decided (Jan) — 2026-08-28, second answer of the day

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Where a review session pushes its findings file | **B — `claude/dev`, beside the code it describes. Nothing in the review loop goes to `main`** | Asked because the reviewer of that day had followed the documented rule and pushed to `main`, and Jan had sent an earlier round to `claude/dev` by hand; deciding it per round was the actual cost. The older rule existed so that `main`'s copy kept the findings as the reviewer wrote them while a fixing session answered a separate copy on `claude/dev`. With one copy there is nothing to keep in step, and the original wording is not lost — `git show <review-commit>:docs/review/findings/<file>` prints it exactly. It also removes the trap the old arrangement had: two files with the same name and different `Status:` lines, and a reader with no way to tell which one they had opened. Considered and rejected: **A**, keeping `main`. The `main` copy pushed under the old rule that day was reverted in the same session rather than left as a duplicate. Written into `docs/review/README.md` (the cycle diagram and the Branches table), `docs/review/PROMPT.md`, `docs/review/FIX-PROMPT.md` and `CLAUDE.md`, so it is a rule rather than a per-round decision. **`main` now means "last released" and nothing else: no session writes to it, findings included.** |

## Decided (autonomous) — 2026-08-28, WP9 review-fix session

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Modelling core's fallback to the tracker's default status (finding F01) | **Draw it, as a dotted arrow that is not a rule** | `Issue#new_statuses_allowed_to` ends with `statuses << default_status if include_default \|\| (new_record? && statuses.empty?)`, and Redmine's own `load_default_data` seeds **no** `old_status_id = 0` row — so on a freshly installed Redmine the drawing reported every status as unreachable from a new issue and collapsed into a band. The fallback is now an `Edge` carrying `fallback: true`, drawn dotted with a legend sentence naming it as Redmine's behaviour rather than a rule anyone wrote, and labelled as such in the table. **`empty_workflow?` counts `stored_edges`**, so Redmine having a default cannot make an own *empty* workflow read as one somebody filled in (INV-3). Deliberately narrow: only a workflow with *no* rule out of the entry node gets the arrow. Core's real condition is that the list came back empty *for the reader*, so a workflow whose only entry rules are author- or assignee-only also falls back for everybody else — but the drawing has no reader to judge a condition against, and an arrow beside a rule already pointing at the same status would say one move twice. Considered and rejected: leaving the fallback out and explaining it in prose beside the drawing, which leaves the reachability diagnostic wrong. |
| 2026-08-28 | A workflow with nearly every move permitted (finding F03) | **Say so and fold the drawing into a `<details>`; keep longest-path ranking** | Redmine's default workflow is *complete* — every status may become every other — and the layered picture of one is a column per status with an arc between every pair, unreadable at six statuses. The finding's first suggestion, ranking by shortest path from the entry node, was **investigated and not taken**: BFS layering does not keep the property a layered drawing needs (for an edge `u → v` it only guarantees `layer(v) ≤ layer(u) + 1`, so forward edges can end up inside a layer or pointing leftwards), and it would not remove the arcs — a complete graph over five statuses still has twenty edges between the members of one layer. So the finding's second suggestion is the whole fix: `Result#dense?` (at least four statuses, at least nine tenths of the possible moves present, entry arrows excluded, integer arithmetic), a sentence, and `<details>` — plain HTML, no JavaScript, no stylesheet the plugin does not ship. Reversible by deleting one branch in `graph.html.erb`; the two thresholds are one constant each. Considered and rejected: deleting the drawing in that case, which hides data the reader may still want. |
| 2026-08-28 | The band of unreachable statuses (finding F04) | **Rank it with the same three phases, on its own sub-graph** | A single row in query order was right for the one or two statuses the band was designed for and wrong the moment several of them had edges among each other: every such edge bowed under the same row and a dozen near-identical arcs is a picture that claims to inform and does not. `WorkflowGraphRanking` now takes `roots:`, and the band is ranked with **every** band node a root — the band has by definition no single starting point, and taking them all is also what guarantees no second band appears inside the first. Cost: one extra ranking pass over a small sub-graph. Considered and rejected: capping the band at a few nodes and saying how many more there are, which hides exactly the statuses the band exists to show. |
| 2026-08-28 | The legend under the drawing | **Only the sentences about a kind of arrow that is on the page** | It named a dashed arrow whether or not the drawing held one, which is instructions for a thing that is not there — and the third kind of arrow made the question worth answering rather than tolerating. The legend also moved into `_graph_figure.html.erb` with the SVG, so that folding the drawing away folds its legend with it. |
| 2026-08-28 | The panel's "no change of status is permitted" (finding F02) | **Absolute only when every one of the reader's roles is in that state** | Keyed on `uniform_state`, which is the same question the diagram screen asks and answers the same way, so the two screens now say the same thing about the same situation. One new key in eight locale files. |
| 2026-08-28 | Separating adjacent action links (finding F05) | **A pipe, which is Redmine's own idiom** | `app/views/projects/show.html.erb` puts one between *Summary*, *Calendar* and *Gantt*. Chosen over a `contextual` block (wrong element inside a table cell) and over a CSS separator (the plugin ships no stylesheet, and an inline style is one a theme cannot reach). |
| 2026-08-28 | Where the drawing's extent is measured | **A class of its own, `Services::WorkflowGraphExtent`** | `WorkflowGraphLayout` crossed `Metrics/ClassLength` again (201/200) once the band ranking went in — the eighth time this repository has taken that signal. "How far the finished drawing runs" is a real subject with a trap of its own: measuring over the boxes alone clips every arc that bows outside them, silently, and that already has a spec. A dead copy of `both_reachable?` came out with it. |
| 2026-08-28 | Version number for this round | **No bump; the fixes fold into the unreleased 0.1.6 entry** | Same reasoning the 0.1.5 entry records: 0.1.6 has never been released (`main` carries 0.0.3, there is no tag), and these are corrections to the very feature 0.1.6 introduces. A reader looking for "when did the diagram arrive" finds one heading, describing what it actually does. |

## Decided (autonomous) — 2026-08-28, second WP9 review-fix session

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Where the project copy hooks in (finding F01) | **`model_project_copy_before_save`, with the work in `Services::ProjectWorkflowCopier`** | `Project#copy`'s list of things to copy is a local array of method names and offers no other seam; the hook is called with the source and the destination inside core's own transaction, identically on 5.1, 6.1 and 7.0. Scopes are written before rules, and only the rules a *source* scope makes visible are carried — a rule row the resolver ignores where it is now is one the copy has no use for either (INV-3). A failure is deliberately not rescued: it is inside core's transaction, so raising rolls the whole copy back and says so, where rescuing would hand the operator a project that looks copied and quietly permits more than the original. Considered and rejected: patching `Project#copy` itself (a sixth copied core method in the digest table, for a seam core already provides). |
| 2026-08-28 | Whether the project copy takes the scope lock the other four write paths take | **No, and `docs/design.md` now names it as the fifth path and says why** | There is nothing to contend for: the target project was created a few statements earlier inside the same transaction and no other request has seen its id, and the copier refuses outright if that project already carries any scope of its own. The reason this is written down rather than simply omitted is that `docs/design.md` already records how a counted claim with a path missing produced finding F01 of 2026-08-27 — so the count moved from four to five in the same commit as the path. |
| 2026-08-28 | What a copy does to a target that already runs its own workflow | **Nothing at all — `[0, 0]`, no scope and no rule written** | "Copied over" is not one of INV-3's three actions, and a project that has already decided something about its own workflow must not have that decision replaced by a copy it did not ask for. Core only ever calls this on a project it has just created, so on the real path the guard never fires; it exists so that a console or a future caller cannot use the copier as an undocumented fourth action. |
| 2026-08-28 | The accessible label's counts (finding F03) | **Count statuses excluding the entry node and transitions excluding the fallback, and name the fallback in a clause of its own** | The previous session had left the fallback in the count deliberately, on the grounds that the number a reader of the picture wants is the number of arrows — and `docs/STATE.md` said so. It is still the wrong number here, because the sentence says *transitions*, and the entry node counted as a status is unambiguously wrong on top of it: a six-status workflow was announced as seven, in the one sentence a screen-reader user hears before deciding whether to read on. A separate locale key rather than a third interpolation, so the clause can be absent without leaving a sentence that has to read well both ways; eight locale files, one new string each. |
| 2026-08-28 | The three query services holding a base relation with no project_id (finding F02) | **Make the shape impossible, not merely commented** | `TransitionQuery` and `PermissionQuery` now go through `WorkflowPopulations`, which was extracted for exactly this split and whose own comment argues this case; `StatusListQuery` keeps its local shape but takes the project_id as a positional argument of the one method that builds a relation, the way `WorkflowPopulations.relation` does. The finding offered a comment naming the three as deliberate — the cheap answer — and said itself it is not as good. A `plugin_conventions_spec.rb` example greps for the construct and checks the *statement*, not a window of lines, so a base relation given its project by a later statement does not clear it. |
| 2026-08-28 | What `WorkflowPopulations` answers for a blank project_id | **The generic population, not nothing** | Routing the two resolver paths through it would otherwise have changed behaviour: an issue with no project yet reads the generic workflow, which is the choice `Issue#tracker=` records in its own comment and `Issue#new_statuses_allowed_to` already made. Since no project means no scope can exist, the Resolver already answers "nothing overridden" for one — dropping the extra guard is the whole change, and the relation still carries an explicit `project_id: nil` (INV-4). Two new examples pin it, and both are red with the guard back in. |
| 2026-08-28 | Version number for this round | **No bump; it folds into the unreleased 0.1.6 entry** | Same reasoning as the two rounds before it: 0.1.6 has never been released (`main` carries 0.0.3, there is no tag). The project copy is an `### Added` bullet of its own in that entry rather than part of the diagram bullet, because it is not about the diagram. |

## Decided (Jan) — 2026-08-28, third answer of the day

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Should *Copy project* have a checkbox for the project's own workflow, like the ones it has for issues and the wiki? | **Yes** | The reason the same day's entry gave for not adding one was wrong on a fact: it costed a checkbox as a sixteenth Deface anchor, and core renders `call_hook :view_projects_copy_only_items, project: @source_project, f: f` inside the copy form's own fieldset on 5.1, 6.1 and 7.0 — a plugin extension point for precisely this. **INV-9 stays at fifteen.** Built as a `Redmine::Hook::ViewListener` with `render_on`, so the markup is a partial rendered through the calling view and is core's own `<label class="block">` verbatim, `only[]` name included (core's toggle-all link selects on that name, so it toggles ours too). |

## Decided (autonomous) — 2026-08-28, the copy-form checkbox

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Ticked or unticked by default | **Ticked, like every one of core's eight items** | It keeps the behaviour shipped a few hours earlier as the default, it matches the form the operator already knows, and — the part that is not taste — it means the parameter can only ever *narrow* what a copy carries. A box that had to be ticked to include the workflow would be a request parameter that widens the result, which is the shape INV-7 exists to keep out even on an administrator-only screen. |
| 2026-08-28 | Shown always, or only when the project has a workflow of its own | **Always, with the count, exactly as core shows *Boards (0)*** | Core's list is a complete statement of what a copy will and will not carry, and an item that disappears at zero makes it an incomplete one. *Project workflows (0)* also tells the reader something true and useful. Reversible with one guard in the partial. |
| 2026-08-28 | How the checkbox reaches the model hook, which core hands no options | **On the destination project object, set by a four-line `Project#copy` delegate** | Not `RedmineProjectWorkflows::Current` and not any other process-wide store: the destination is the one object both halves already hold, it cannot outlive the copy, two concurrent copies cannot see each other's answer, and there is nothing to reset. The delegate calls `super` and is the nineteenth entry in the core-drift digest table — which is right, because if core changed how it reads `options[:only]`, or moved the hook out of `#copy`, the checkbox would silently stop being honoured. |
| 2026-08-28 | The checkbox's value in `only[]` | **`project_workflows`** | Core intersects its own eight names with what was submitted, so a name it does not know is ignored rather than dispatched to a `copy_<name>` method that does not exist. A collision would need core to add per-project workflows of its own, at which point this plugin has a larger question than a form value. |
| 2026-08-28 | What a malformed `only` means | **Narrow, never widen** | `Array.wrap` and `to_s` on each entry, so a hash or a number simply fails to match the key and the workflow is not copied. Core's own `to_be_copied & Array.wrap(options[:only])` behaves the same way for its eight, so a hand-built request gets one consistent answer rather than two. |
| 2026-08-28 | Guarding a core extension point that is not a Deface anchor | **The same discipline INV-9 asks for: a spec that asserts the checkbox reaches the rendered page** | `spec/controllers/projects_copy_form_spec.rb`, on the real `GET /projects/:id/copy` on every supported version. An extension point can be removed as silently as a selector can stop matching — core would just stop calling it, the checkbox would vanish, every copy would carry the workflow again, and nothing else in the suite would notice. |

## Decided (Jan) — 2026-08-28, fourth and fifth answers of the day

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | What should the plugin do on a Redmine minor nobody has verified it against? Warn, or block writes until an administrator acknowledges the version? | **Warn** | A block bricks an installation on an upgrade the administrator may have had no choice about, and it disables precisely the screens where they would put it right. Jan asked the follow-up question that made the answer better than either option: *is there a way to check whether anything actually changed in the new minor — because then it is safe?* There is, and the machinery was already in the repository. `CoreMethodDigest` computes a digest of core's own body for every method the plugin shadows, and it does not need a test suite: **19 methods in 34.5 ms**, measured on a running 5.1 host through `rails runner`. So the answer is three states rather than two, and it is ADR-002: *verified* (silent, no digest work at all), *unverified with no drift detected* (a log line and a diagnostics entry), *unverified with drift* (a warning naming which methods changed and where core defines them). What the check proves and what it does not is written into the ADR rather than left to be assumed — it proves the copied bodies are unchanged, not that core still calls them the same way, not that private helpers they call are unchanged, and not that the Deface anchors still match. |
| 2026-08-28 | In the hardening track, does the owned-administration work come before or after the write-coordination work? | **Owned screens first (WP12), then write coordination (WP13)** | WP13's lock service touches all four write paths, and WP12 rewrites where two of them live. The other order does the work twice. |

## Decided (autonomous) — 2026-08-28, the hardening-track plan

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Whether to move the rules out of core's `workflows` table into a plugin-owned one | **No. ADR-001 stands** | The tempting version of "rewrite it now while nothing is deployed". It would remove the core-table migration, the destructive uninstall and the MySQL table rebuild — and it would **not** remove the actual upgrade tax, which is the replacement of core's *query* methods; those have to be replaced either way. What it would cost is the cascade deletes real foreign keys give today, the reuse of `WorkflowTransition` / `WorkflowPermission`, the reuse of core's matrix partial, and one-query resolution of both populations. Recorded as considered-and-rejected in ADR-003 so the next reviewer proposing it can read why. |
| 2026-08-28 | Whether to cut the workflow diagram, as one review proposed | **No. It becomes switchable with a size ceiling instead** | It is finished, it is pure functions with about 800 lines of specs, and it is the plugin's clearest difference from Jira. The maintenance argument against it is answered by making it a feature that can be turned off — a feature nobody has to defend on an upgrade — rather than by deleting working code. |
| 2026-08-28 | Whether an oversized bulk write should become a background job | **No; bound it instead** | Redmine 5.1's default ActiveJob backend is the async adapter, which is not something a workflow write may depend on. Project the row count, confirm above the threshold the plugin setting already carries, refuse above a ceiling. The transaction stays: a half-written selection is worse than a refused one. |
| 2026-08-28 | Where the review of 2026-08-28 that ran no neighbouring plugins sits beside the one that ran forty-four | **Both files stand; neither supersedes the other** | They found disjoint sets. The whole-stack run found the blocker (a permission name captured by a neighbour) and the version-probe defect; the audit found the `WorkflowsHelper` prepend, the SQLite migration abort and the issue-status deletion that empties a project scope. The audit's F01 is explicitly calibrated against the whole-stack run: none of the forty-four neighbours triggers it today, so it is latent for Jan and live for a public release. Saying that in the finding is what keeps its severity honest. |
| 2026-08-28 | Whether the ChatGPT review Jan commissioned gets a findings file of its own | **No; its findings are folded in with attribution** | Four of its points were already known or already answered, one (mixed valid and invalid role ids on the graph) was genuinely new and is `2026-08-28-claude-audit.md` F05 with the credit in the finding, and one (concurrent generic writes) is real but was attributed to the plugin when it is core's race inherited — the correction is in F07. Its two headline ratings are not carried over: *Security: MEDIUM* is supported by none of its own findings, and *Test confidence: MEDIUM* was reached without running the suite, which its own verification section says. |

## Decided (Jan) — 2026-08-28, the permission rename

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | The permission `manage_project_workflow` collides with `redmine_custom_workflows`, which registers the same name with an empty action hash and loads first — so every write action of this plugin answers 403, administrators included. Rename only the colliding half, or both? | **B — rename both:** `view_project_workflow_rules` / `manage_project_workflow_rules` | The migration had to be written either way and carrying a second name through it is one entry in a hash, where a permanently lopsided pair of names on the role form is forever. The labels an administrator reads are unchanged in all eight locale files — only the keys moved — so nothing was retranslated and no unreviewed locale gained a new string. Finding F01/F10 of `2026-08-28-claude-plugin-compat-5.1`, measured on a 45-plugin Redmine 5.1 host. |

## Decided (autonomous) — 2026-08-28, the permission rename

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | What migration 006 does with a legacy `manage_project_workflow` grant on an installation where the neighbour still registers that name | **Nothing, and it says so** | The stored symbol is a bare name: a role may hold it for `redmine_custom_workflows` rather than for this plugin, and nothing distinguishes the two. Renaming it takes the neighbour's permission away; adding ours beside it widens what the role may do, which is the one direction a migration must never move on its own. So it leaves the grant alone and prints what to grant instead — and on such an installation this plugin's write screens have never worked, so nothing that worked stops. The name that is *not* claimed elsewhere still moves: one collision does not strand the pair. |
| 2026-08-28 | How the migration decides that a legacy name is ambiguous | **`Redmine::AccessControl.permissions.any? { it.name == legacy }`, not `Plugin.installed?(:redmine_custom_workflows)`** | It is the question that actually decides ambiguity, and it stays right if the neighbour is renamed, removed or replaced by some other plugin claiming the name. By the time a plugin migration runs, every plugin has registered. Known limit, written into the migration rather than hidden: a legacy symbol left behind by a plugin that has since been *uninstalled* reads as unambiguous and is renamed — there is nothing in the data to tell that grant from one of ours, and never migrating anything would cost every installation its role configuration to protect a case that leaves no trace. |
| 2026-08-28 | Whether the permission **labels** change with the keys | **No — keys only** | The label is what an administrator reads on the role form, and *View the project's workflow* still says exactly what the permission does. Changing the text would mean new strings in `de`, `es`, `fr`, `it`, `pl` and `pt`, which are translated but unreviewed — six unreviewed strings bought for no gain. `spec/locales_spec.rb` parity is untouched. |
| 2026-08-28 | How the plugin decides whether the host draws SVG icons (finding F02) | **`Redmine::VERSION::MAJOR >= 6`, never `respond_to?(:sprite_icon)`** | A method name is not owned by Redmine: on 5.1 the `redmineup` gem back-ports a `sprite_icon` for every RedmineUP plugin, and `redmine_ai_triage` back-ports another, so the old test answered *true* on a host with no sprite sheet. The two spec files that restated the same expression now call the production predicate, so no neighbour can make code and test wrong in the same direction. Three examples pin it, red on 5.1 and 7.0 respectively plus a grep for the construct. |
| 2026-08-28 | How the specs get past a neighbour's authorization gate on core's issue pages (finding F04) | **A named list of one, guarded on the permission being registered** | The finding asked for it to be *computed*; it cannot be. `redmine_view_issue_description` declares its permission with an empty action hash and puts the gate in a controller `prepend`, so `AccessControl` holds nothing connecting it to `issues#show`. The guard is what keeps the accommodation honest: on this plugin's own CI the permission is not registered and the helper does nothing at all. Finding marked `adjusted` rather than `fixed`, because the fix is not the one the reviewer proposed. |
| 2026-08-28 | Version number for this round | **No bump; it folds into the unreleased 0.1.6 entry** | Same reasoning as the four rounds before it: 0.1.6 has never been released (`main` carries 0.0.3, there is no tag). The rename is a `### Changed` bullet of its own because it is the first thing an upgrading administrator needs to read, and the icon fix is a `### Fixed` bullet because it is a defect in what 0.1.6 already shipped. |

## Decided (autonomous) — 2026-08-28, WP10's four defects

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Where `WorkflowsHelperPatch` attaches | **Both controllers' helper chains, and neither `WorkflowsHelper` nor one controller** | `WorkflowsController` owns the administration screens and `ProjectWorkflowsController` renders core's own `workflows/_form` for the project matrices, so naming one would leave the other's cells unrendered. The reasoning against the prepend is `ProjectsHelperPatch`'s, one helper further on; the difference is that no neighbour on Jan's 45-plugin host alias-chains `WorkflowsHelper`, so this was latent rather than live and needed a spec rather than a bug report. ADR-003 deletes this patch outright, so the move is a stopgap with a known end date — worth having because WP12 is several sessions away. |
| 2026-08-28 | What that does to the core-drift gate | **`CoreMethodDigest` learns both attachment styles** | It reached core's body through `super_method`, which answers nil once the patch is no longer in the owner's ancestors — so the three `WorkflowsHelper#*` digests would have vanished silently and the gate would have covered sixteen methods while the YAML still listed nineteen. It now asks whether the patch is in `owner.ancestors` and takes the method itself where it is not. Found while running the suite, not while writing the fix; without it the drift spec would have gone red for a reason that had nothing to do with core. |
| 2026-08-28 | The near-miss in the alias-chain spec | **Recorded in the spec, not quietly corrected** | The first version copied `WorkflowsHelper`'s own definition by walking `super_method` down to it — the shape `projects_settings_tab_spec.rb` uses for a neighbour loading *before* this plugin, which is the safe order. With the prepend restored, exactly one of five examples failed: the three behavioural ones could not fail. Rewritten with a plain `alias_method`, which is what a neighbour loading *after* us does, three of five go red including both rendering examples. The comment in the spec says so, because "a test that fails on the old code" is a gate that can be passed by accident. |
| 2026-08-28 | The timestamp literal in the three raw-SQL sites | **Plain, not the `TIMESTAMP '...'` type keyword** | The keyword form is standard and says what it means, in a dialect SQLite does not have — where migration 004 aborts with 001..003 already committed and leaves the installation carrying `workflows.project_id` with no scope table under it. Redmine ships SQLite support in its own Gemfile and `database.yml.example`. `dev/check-backfill.sh` is what proves nothing was lost: it asserts the backfilled timestamps are UTC, which is the property the keyword form existed to make explicit. |
| 2026-08-28 | A graph request naming one good role id and one bad one | **404, as the method's own comment had promised since WP9** | It answered only on an *empty* selection, so such a request drew the offered role under a heading claiming both. The de-duplication rule is the copy screen's: an id repeated in a selection is one selection, not a missing record. |
| 2026-08-28 | `Metrics/ClassLength` at 204/200 on `ProjectWorkflowsController` | **Extract, do not raise the limit** | The controller's own comment says what crossing it means, and this is the third time: `MatrixParams` at 203, `MatrixReporting` at 202, and now `GraphSelection` at 204. Every method in it is private, because a public instance method of a controller is an action. |

## Decided (autonomous) — 2026-08-28, the PostgreSQL failure of `cea14d8`

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Making the timestamp literal portable without breaking PostgreSQL | **Move the `DISTINCT` into a subquery; no adapter conditional** | Measured on PostgreSQL 16: a bare literal in a *plain* select list is coerced against the target column, and under `DISTINCT` it is not — `DISTINCT` has to type the column to compare it, and `unknown` resolves to `text` before the INSERT sees it. The obvious repair, branching on `adapter_name`, was rejected: one statement shape that every adapter reads the same way is better than a conditional, and `CAST(... AS timestamp)` is not a shared form either — MySQL has no `TIMESTAMP` cast target and SQLite would give it NUMERIC affinity. |
| 2026-08-28 | The claim in migration 004's comment that PostgreSQL coerces the literal | **It was right about the statement it measured and wrong about this one** | Recorded rather than quietly replaced, because the same sentence had already survived one review round. The comment now carries both measurements and the narrow rule they produce: never put an untyped literal in the select list of a `DISTINCT`, a `UNION` or a `GROUP BY`. |
| 2026-08-28 | A guard that passes by accident | **Twice in one session, and both are written into the spec that failed** | The alias-chain spec modelled the safe load order and only 1 of 5 examples went red; the `DISTINCT` conventions grep stripped every line starting with `#`, which is what a heredoc line opening `\#{now}` looks like, so it was green against the exact shape it forbids. Both were found by reverting the fix and running, and neither by reading. CLAUDE.md's gate is "a test that fails on the old code" — the point is that it has to be *observed* failing. |

## Decided (autonomous) — 2026-08-28, WP11's manifest

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Where the manifest's data lives | **`lib/redmine_project_workflows/compatibility.yml`, beside the module that reads it** | It was `spec/upstream/core_method_digests.yml`, which made it a test fixture — and half of what it knows (which Redmine minors have been measured) is a fact the *running* plugin needs in order to tell an administrator that nobody has tried this on their Redmine. A file under `spec/` cannot be read by a production code path without saying something false about what it is. |
| 2026-08-28 | Whether the README's Compatibility section is generated from the manifest | **No — hand-written, and asserted against it** | ADR-002 says "generated"; prose generated from YAML is neither good prose nor a good manifest, and the section now explains the three states in sentences no table would produce. What matters is that the two cannot disagree, so four examples in `spec/compatibility_spec.rb` read the section and compare the versions, the databases and the Rubies it names against the manifest. The claim sentence is parsed rather than the whole section, because `0.1.0` and `Ruby 3.2` are both `\d+\.\d+` and neither is a supported Redmine. |
| 2026-08-28 | How a spec reaches the two states no host can be in | **A settable `data_file`, and a synthetic manifest on disk** | Every host the suite runs on is a verified one by construction, which is the same shape as the defect ADR-002 exists to fix. Stubbing `verified?` would test the branch and not the module; pointing it at a real YAML file whose only minor is `99.9` exercises the load, the comparison and the log line, with the digests really measured on the host and only the table fictional. |
| 2026-08-28 | Comparing an unknown minor against which verified one | **The newest** | An unknown minor is almost always a newer Redmine, and "identical to the newest Redmine this was tested on" is the sentence worth being able to say. Matching some older entry instead would be a weaker claim reported as the same one. |
| 2026-08-28 | `Rails.logger` in `Compatibility`, against the convention that only `WriteLog` logs | **Named in the convention example, with the reason** | The rule is that a *write* may log ids and counts only, and that one service holds it. The boot line is not a write: it runs once per process, before any request, and the only values in it are a version number and the names of core's own methods. Widening the allowlist without saying why would have been the weakening; the example now names the file and the sentence that exempts it. |
| 2026-08-28 | `WorkflowTransition.replace_transitions` differs between 6.1 and 7.0 | **Nothing follows; the difference is recorded** | The first thing the extended gate found. 7.0 rewrote the method to index existing rows by `[old status, new status, tracker, role]` instead of scanning them per cell — the same rules with a hash in front of them — and the plugin replaces that method outright rather than copying it, so there was nothing to follow. Written into the manifest's header because "no change was needed" is a conclusion somebody reached by reading, not a gap. |
| 2026-08-28 | An example that asked the manifest what it meant to ask the measurement | **Rewritten, and the near-miss recorded in the spec** | `covers the class methods…` asserted `digests_for(host_minor).keys` — the checked-in table — and stayed **green** with the singleton targets removed from `CoreMethodDigest`, because the table still listed what the gate had stopped measuring. Found by reverting `TARGETS` on a host and watching it not fail. That is the third guard in two sessions that passed by accident, and the second found only by reverting-and-running. |

## Decided (autonomous) — 2026-08-28, WP11's diagnostics page

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Where the diagnostics page is reached from | **An `admin_menu` entry of its own** | ADR-003 accepts a second administration entry point and verified `Redmine::MenuManager.map :admin_menu` as a stable extension point on all three versions, so the page needs no Deface anchor and INV-9 stays at fifteen. The entry passes core's own pair of options — `icon: 'summary'` and `html: { class: 'icon icon-summary' }` — because 6.0 and later read the first and 5.1 reads the second, and **no** `plugin:` option, which would send `sprite_icon` looking for a sprite sheet in this plugin's assets. `summary` is in core's sheet on 6.1 and 7.0 and `.icon-summary` is in 5.1's stylesheet; both were checked rather than assumed. |
| 2026-08-28 | How the page is authorized | **`require_admin`, and no permission of its own** | Every fact on it is about the installation rather than about a project, so INV-7's question — which project does this action authorize against — has no answer. A permission would invent one. |
| 2026-08-28 | Whether the Deface overrides get a pass/fail tick | **No; they are a listing** | There is no honest check to be had. A registered override is not a *matching* one — Deface reports nothing when a selector finds no anchor, which is why INV-9's assertions exist — and an override file that fails to load already stops the host from booting. A green tick would be a claim about nothing. The spec compares the number listed against the number the plugin's own override files declare, read from disk, so the page and the files cannot drift; ADR-003 reduces the list to two, at which point a runtime anchor check becomes a line. |
| 2026-08-28 | How the permission check finds this plugin's permissions | **By their actions, never by their names** | The failure being looked for is precisely a name that resolves to another plugin's registration. A search by name finds the impostor and reports it as ours. Selecting the registrations whose action list names one of this plugin's own controllers finds *ours* even when a neighbour has captured the name, and object identity against `AccessControl.permission(name)` is then the question that matters: which of the two does `User#allowed_to?` get? |
| 2026-08-28 | The attachment table reporting a correctly applied patch as missing | **A fourth element naming the module to look for** | `IssuesControllerPatch` puts `ProjectWorkflowMapsHelper` into `IssuesController`'s chain and nothing of its own — there is no core method to override, only a helper a Deface override calls from a view core owns. Asking for the patch module reported it as not attached. Found by the example that asserts every patch is attached on this host, which is the example that would otherwise only ever have said "true, thirteen times". |
| 2026-08-28 | Sentences assembled in Ruby for the page | **None; the checks carry facts and the view carries the keys** | The first draft built "claimed by another plugin -- N registrations..." inside the service. English assembled in Ruby is English nobody can translate, and this plugin ships eight locale files that a spec keeps in parity. The two check structs now carry a name, a boolean and a number. |
| 2026-08-28 | Whether WP11 adds a CI job of its own | **No** | ADR-002's decision 5 is that CI fails where runtime warns, and the question is asked inside the rspec job on each of the nine cells — which is where the host actually is. A separate job would either duplicate the matrix or ask the question somewhere it cannot be answered. The `skip` becoming a failure is the whole change. |

## Decided (autonomous) — 2026-08-28, WP11's review pass

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | A Ruby that cannot read core's source, on a Redmine the manifest does not list | **A fourth state, `:unmeasured`, with a sentence of its own in all eight locales** | ADR-002 names three states, and the second one's sentence is "no drift was detected". On a Ruby without `RubyVM::AbstractSyntaxTree` nothing is measured, so that sentence would be a claim about a measurement that never ran — and **no supported host is such a Ruby**, which is precisely why the claim would have gone unchallenged forever. One key in eight files is a small price for a page whose whole value is that somebody trusts it. Reversible: delete the state and the key. |
| 2026-08-28 | The locale example that rendered eight languages and asserted nothing about the language | **Assert the translated title first, then the absence of a missing translation** | It could not fail: a language that never took effect renders in English, where nothing is missing. Adding the assertion turned it red on 5.1 with `I18n::InvalidLocale`, which is how the version difference below was found — 6.1 and 7.0 set `config.i18n.available_locales` from core's own locale files and 5.1 does not, so a 5.1 host under `RAILS_ENV=test` offers `:en` alone. The example now iterates the locales the host actually has: strong on two of the three versions, honest on the third, and `spec/locales_spec.rb` is what asserts the eight files agree on every cell. |
| 2026-08-28 | Which of Redmine's boxes the compatibility state sits in | **A plain paragraph when verified; `.warning` for the other three** | Read out of core's stylesheet rather than chosen: `.nodata` and `.warning` are **one rule** on 5.1 and on 7.0 — the same amber — so `.nodata` is a warning wearing another name, and it was carrying the sentence "this Redmine is one the plugin is tested against". A bare `.notice` is unstyled, because the green box is `div.flash.notice` and belongs to a flash. Redmine has no neutral box, so good news gets no box, and the three states that are not reassurances share the amber one with the sentence carrying the difference — colour supporting the text rather than carrying it. |

## Decided (autonomous) — 2026-08-28, WP12 (1/2): the plugin's own administration area

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | What the new area is called, in routes and in code | **`project_workflow_rules`, matching the permission pair** | The two permissions were renamed to `view_/manage_project_workflow_rules` on 2026-08-28 for a reason that applies here too: a name has to say what it governs. `/project_workflow_rules` is this plugin's rules for projects, and it cannot collide with core's `/workflows`. The action names inside it are core's — `index`, `edit`, `update`, `permissions`, `update_permissions`, `copy`, `duplicate` — so a reader who knows Redmine's workflow routes knows these. |
| 2026-08-28 | Whether the new screens still offer the generic workflow in their project selector | **Yes** | ADR-003 moves *projects* off core's screens; it does not make the generic workflow unreachable from the plugin's. Copying the generic workflow into a project is the main thing the copy screen is for, and editing "the generic workflow and these three projects" in one matrix is the feature that made a third `no_change` cell state necessary in the first place. Core's screen is now the one that offers nothing but the generic workflow. |
| 2026-08-28 | `require_admin` before the finders, where core has it after | **Before** | Core declares `find_trackers_roles_and_statuses_for_edit` ahead of `require_admin`, which is how `/workflows/edit` came to answer an anonymous visitor 404 for a project id that does not exist and a login redirect for one that does — a list of existing project ids, handed out before anybody had checked who was asking (finding G01). On core's controller the plugin could only work around it with a guard clause inside the finder, because a scoped `prepend_before_action` would *delete* core's unconditional registration. On its own controller the order is simply right, and an example asserts the two ids are indistinguishable. |
| 2026-08-28 | A copy whose request names no target project at all | **Refused on the plugin's screen; unchanged on core's** | Core's `duplicate` treats a missing target as the generic workflow, and core's screen keeps doing exactly that. The plugin's screen always renders the target selector with the generic workflow preselected and its blank option disabled, so a request carrying no target project is a deliberate deselection or a hand-built POST — and every write on that screen first *deletes* what the target pair had. Reporting it is the safe reversible default (the same reasoning as finding C01: the destructive default has to be the visible one). Reversible in one branch. |
| 2026-08-28 | Where the matrix cell helpers live once nothing prepends onto `WorkflowsHelper` | **`ProjectWorkflowMatrixHelper`, an ordinary plugin helper** | ADR-003 deletes `WorkflowsHelperPatch`, but only one of its methods is a patch on core: `options_for_workflow_select`. The other four are cells and labels the plugin's own screens need. They move to `app/helpers`, are named with `helper` in each of the three controllers that render a matrix, and stay out of `WorkflowsHelper` for exactly the reason the patch had to (finding F01: a neighbour's alias chain copies a prepended method and loses its `super`). |
| 2026-08-28 | A copy of a core body that leaves the `Patches` namespace | **It stays in the drift gate; `TARGETS` takes non-patch modules** | `CoreMethodDigest` discovers the methods it watches from the module that holds them, so moving `transition_tag` out of `Patches` would have moved it out of the gate — silently, which is the failure mode the gate exists for. Two entries added: `ProjectWorkflowMatrixHelper` against `WorkflowsHelper`, and `ProjectWorkflowRulesController` against `WorkflowsController`. A copy is a copy wherever it is filed. |
| 2026-08-28 | Reaching core's body when *another* module of the plugin's is also in the chain | **Walk down past every plugin-owned definition** | `core_source` asked "is this module in the owner's ancestors?" and stepped once. That answers a prepended patch and a helper-chain module, and gets the third case wrong: `ProjectWorkflowRulesController` holds copies of `WorkflowsController` bodies that `WorkflowsControllerPatch` still prepends, so one step lands on the plugin's own body and digests it as core's. Walking while the definition is ours answers all three and stops being an assumption about attachment. |
| 2026-08-28 | Rails' generated methods appearing as copied core bodies | **Skipped, by the leading underscore that marks them** | `layout 'admin'` defines `_layout`, on core's controller and on the plugin's alike, so the gate reported `WorkflowsController#_layout` as a body the plugin had copied — with "core's" definition pointing into the actionview gem. Only reachable because ADR-003 put a *class* in `TARGETS` where every previous entry was a module: a class carries the framework's machinery and a patch module carries only what somebody typed. |
| 2026-08-28 | Where the three scope actions return to | **The plugin's own matrix** | `ProjectWorkflowScopesController` redirected to `edit_workflows_path`. Those three actions are entirely about projects, and after WP12 core's screens cannot show a project's scope at all — sending an operator back to one would land them on a matrix that cannot show what they just changed. |

## Decided (Jan) — 2026-08-28, WP12's cross-link

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Should Redmine's own **Administration → Workflow** carry a link across to **Administration → Project workflows**? | **A — yes, through the Deface override the plugin already has on `workflows/_action_menu`** | Asked at the end of the WP12 (1/2) session with A recommended. It costs one override against the ten being removed, on an anchor already known to match on all three supported versions, and it answers the question somebody arriving at Redmine's screen will actually have: the project selector that used to be there has moved, and nothing else on that page says where. Implemented the same day, on the override that already carried the inventory link — one `Deface::Override.new` rendering two anchors, so INV-9 stays at fifteen now and lands at **five in three files** after WP12's second half, where the inventory half of this override goes and the cross-link stays. |
| 2026-08-28 | The first assertion written for that link | **Rejected: it could not fail** | `expect(response.body).to include('href="/project_workflow_rules"')` is satisfied on **every** administration page whatever the override does, because WP12's `admin_menu` entry renders exactly that href into the `admin` layout. Deleting the link from the override left the example green. Scoped to `div.contextual` it is red on the old code, verified by deleting and running. INV-9's rule — an assertion only that override can satisfy — has now been broken twice in the same way, both times by markup the *layout* contributes rather than the page. |

## Decided (autonomous) — 2026-08-28, WP12 (2/2): core's screens back to stock

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-28 | Which of core's workflow actions the shrunken patch keeps | **`index`, `edit`, `permissions` and the private `find_statuses` — not `update` and `update_permissions`** | ADR-003's decision 3 and the implementation plan both name five actions. Two of them need nothing: core's own `update` and `update_permissions` write through `WorkflowTransition.replace_transitions` and `WorkflowPermission.replace_permissions`, which the plugin's singleton patches already route to its writers with `project_id` fixed at `nil` (INV-1), so a generic save reaches generic rows and no others. What both lists missed is `find_statuses` — the "only display statuses that are used by this tracker" checkbox runs a `workflows` query with no `project_id` predicate, so on an installation where one project has taken a tracker over the generic matrix grew rows for statuses no generic rule mentions (INV-4). The ADR carries a dated "Measured result" note saying so rather than being edited. |
| 2026-08-28 | What core's screens do with a `project_id` in the request after WP12 | **Ignore it** | Nothing in the shrunken patch reads `params[:project_id]`, so a bookmark from an earlier alpha names nothing and reaches nothing (INV-7). The alternative — answering 404 or redirecting to the plugin's screen — would mean reading a parameter in order to refuse it, which is more code on a core controller for a case only an old bookmark produces. Asserted from both ends in `spec/controllers/workflows_controller_spec.rb`, and the README says what to do with such a bookmark. |
| 2026-08-28 | Where `ProjectWorkflowMatrixHelper` is attached to core's controller once `WorkflowsHelperPatch` is gone | **A new `Patches::WorkflowsControllerHelperPatch`, shaped exactly like `IssuesControllerPatch`** | A bare `WorkflowsController.helper(...)` in `apply_patches` would be an attachment the diagnostics page cannot report: `Diagnostics::ATTACHMENTS`'s discovery guard asserts its rows are exactly `Patches.constants`. The module carries no method of its own and its `ATTACHMENTS` row names the helper to look for, which is the fourth element `IssuesControllerPatch` introduced. It is load-bearing rather than tidy: core's `workflows/_form` renders the row and column actions of WP5, so without it **core's own workflow screen raises `NoMethodError`** — verified by deleting the call and watching eleven examples go red. |
| 2026-08-28 | Where the four partials the deleted overrides rendered now live | **Three move to `app/views/project_workflow_rules/`; `_bulk_undo` stays shared** | `app/views/redmine_project_workflows/` exists because a partial injected into a view core owns needs a path that is not controller-scoped. `_scope_panel`, `_matrix_note` and `_copy_project_selector` are now rendered only from the plugin's own administration views, so they move there. `_bulk_undo` is rendered from the project matrices as well, `_bulk_script` is reached from a helper called out of core's `workflows/_form`, and `_copy_project_workflow` goes into core's project-copy form through a hook — all three stay in the neutral namespace, which is what that directory is for. |
| 2026-08-28 | What happens to the 1,956-line `workflows_controller_spec.rb` | **Merged into `project_workflow_rules_controller_spec.rb`; the rendering half moved to `spec/views/project_workflow_rules/screens_spec.rb`** | The file drove the controller by action name, so the move was the class, five path helpers and the comments that named core's callback order — which is the point: what an administrator can do did not change, and a refactoring that quietly changed it would be worse than one that did not happen. Split by kind rather than kept whole because the Deface spec's rendering groups had to land somewhere too: what each screen renders is now one file, what the controller does is another, and a reader looking for either knows which. A small `workflows_controller_spec.rb` remains, asserting the one property core's screens now have. |
| 2026-08-28 | The INV-9 document-count gate after the counts became small words | **Assert the phrase, not the word** | While the counts were fifteen and twelve, `include('fifteen')` was a real assertion: no document says "fifteen" about anything else. Five and three are ordinary English words that appear in `CLAUDE.md` and `docs/design.md` for a dozen unrelated reasons, so the word alone would have gone on passing over any count whatsoever — a gate that had quietly stopped being one. It now matches `five view overrides` / `five deface overrides` and `in three files`, and it was verified by editing `CLAUDE.md` to a wrong count and watching it fail. |
| 2026-08-28 | Whether the diagnostics page can honestly check a Deface anchor, and how | **Yes: read the template from disk, then ask Deface's own parser and the override's own matcher** | Until now the page said explicitly that it listed what the plugin had *registered*, which is not what it managed to *place*, because at fifteen anchors a runtime check would have been a second test suite. ADR-003 took it to four, and at four it is a table. Two details decide whether the answer is worth anything. The template is read from **disk** by the path Rails' resolver gives, never from `ActionView::Template#source`: Deface's `encode!` rewrites that string in place once a page has been rendered, so a source read there would sometimes already carry the override and the question would answer itself. And the match is decided by `Deface::Parser.convert` plus `override.matcher`, which is the same pair the applicator uses at render time — asking any other way would be a second opinion about a selector rather than the answer. Verified in both directions on a running host: five matched, and a selector pointed at markup no Redmine has came back `:unmatched` with `ok?` false. |
| 2026-08-28 | What an anchor the page could not measure counts as | **Neither good news nor bad — a third state, and not a failure** | The same rule WP11 settled for a Ruby that cannot read core's source, applied to a second measurement. A green tick over a template this process could not read would be the exact failure this page exists to prevent; a red one would send an administrator looking for a defect nobody has established. `:unmeasured` gets its own word in all eight locales, no tick at all, and is excluded from `ok?`. |
| 2026-08-28 | Three links that carried a project into Redmine's own screens | **Repointed at the plugin's matrices** | Found by the review role, not by the suite — and the suite *did* assert their destinations, which is what made it a one-line fix rather than a discovery. The inventory's count cells, its "open the matrices" link and its heading, and the "open the matrix" link on the issue form's workflow panel all built `edit_workflows_path(project_id: [...])`. That worked while core's screens honoured the parameter; since ADR-003 they read no project at all, so the reader would have landed on the *generic* matrix believing they were looking at the project's — silently, with the project named in the link's own label. Nothing else in `app/` or `lib/` links to core's workflow routes now except the one deliberate cross-link. |

## Decided (autonomous) — 2026-08-29, WP13 step 1: one write-coordination service

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | What the generic population's coordination row **is** | **A row on a plugin-owned table, `project_workflow_write_locks` (migration 007)** | The alternative was giving the generic workflow a scope row, and it is the one thing that must not be done: a scope row means *this project decides* (INV-3), and a generic one would be a fourth state in a model whose whole purpose is that there are three. Advisory locks were the other alternative and are not portable — PostgreSQL, MySQL and MariaDB have no such call in common, while `SELECT … FOR UPDATE` is what all three already speak for the scope rows. |
| 2026-08-29 | Whether project writes also take a row on the new table | **No — a project's scope row already is its coordination row** | The plan's key is `(rule_type, project-or-generic, tracker, role)` and that is what a caller names; what it resolves to differs by population, deliberately. A scope row exists exactly when the combination is writable, so "may I write this?" and "nobody else may while I do" are one statement — which is what 0.1.2 built and what the concurrency spec has pinned since. Adding a second row per project combination would double the rows an "all projects" save locks and buy nothing: the project half was never the half with the race. `Services::WriteCoordinator` is the one entry point either way, so there is one policy at the call site even though there are two kinds of row behind it. |
| 2026-08-29 | Where the copy screens take the generic row | **In the model, beside the write — `WorkflowRule.copy_for_project` and `.copy_one_for_project`** | The first draft took it in `CopyScopes#lock_scopes_for_copy`, which is the plugin's own copy controller. That covers one of the two copy screens: **Redmine's own** copy screen writes generic rules through core's `WorkflowRule.copy` → the plugin's `.copy_one` → `.copy_one_for_project`, and never goes near the plugin's controller. Taking it in both model methods covers both screens, and neither is redundant — `.copy_for_project` takes them as one sorted batch, which is what fixes the *order* two concurrent copies take them in, and `.copy_one_for_project` is what Redmine's own screen reaches. |
| 2026-08-29 | The rows are created but never deleted | **Accepted** | The table is bounded by rule types × trackers × roles, the rows carry no data, and the two foreign keys clear them up when a tracker or a role goes. Deleting a row that is not held would be a second race for nothing. |
| 2026-08-29 | No timestamps on the lock table, against `Rails/CreateTableWithTimestamps` | **Cop disabled with the reason in the migration** | The row records no event. A `created_at` would be the first time anybody saved that combination, which nothing reads or shows, and an `updated_at` would never change — two columns that would read as an audit trail beside the real one on `project_workflow_scopes`. |
| 2026-08-29 | `MatrixScope#writable_pairs` after the logic moved | **Deleted rather than kept as a delegation** | RuboCop's `Rails/Delegate` objected to the one-line forwarder, and the cop was right for once: the writers now name `WriteCoordinator.writable_pairs` at the call site, so the thing deciding is the thing named. `MatrixScope` keeps `pair_predicate`, which is what the two writers genuinely share. |

## Decided (autonomous) — 2026-08-29, WP13 step 2: bounded bulk writes

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | What a save is *counted* as | **Workflow rules: (cells submitted) × (workflows the selection covers)** | The unit the row and column actions of WP5 already ask about, so the two dialogs on the same screen mean the same thing by the same word. The projection is exact rather than estimated: `submitted_leaf_count` runs on the writer that is about to run and counts the same leaves `sanitize_and_count` does, so what the screen refuses over and what the writer would act on cannot drift apart. |
| 2026-08-29 | When the Save confirmation asks | **Only when the selection covers more than one workflow** | How many cells there are is decided by the status list and is the same on every save of the screen, so a threshold on the cell count alone would have asked on an ordinary single-workflow save — which is what Redmine has always done and must not grow a dialog. The same condition the page already uses to decide whether to show the bulk note and the *(No change)* option. |
| 2026-08-29 | Where the bulk script is rendered | **Above the form on both administration matrices, not from a row header** | It was rendered lazily by whichever row or column header came first, and the **field permissions** matrix has no row or column actions — so on that screen the script was never on the page and the new handler would have called a function that is not there. Still one `<script>` per page: the helper's guard is unchanged and the header call finds it already done. |
| 2026-08-29 | A save that is refused loses the unsaved matrix | **Accepted** | The redirect re-reads the database, as every other refusal on this screen does. Re-rendering the submitted matrix would mean carrying the payload back through the view, and the operator has already been asked once by then — the Save button's confirmation uses the *same* number against a threshold far below the ceiling, so a request that reaches the refusal has been through a dialog naming it. |
| 2026-08-29 | Whether the ceiling refuses a project's *own* matrix save too | **No — the administration screens only** | `AdminMatrix` is the administration path; a project's own matrix is one project, one tracker and one role by construction, so its projection is the cell count and bounding it would only ever refuse a legitimate save of one workflow. |

## Decided (Jan) — 2026-08-29

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | The default write ceiling for an administration matrix save | **A — 200,000 workflow rules** | Asked at the end of the WP13 session with A recommended, and answered the same day. Jan's question with the answer was whether bulk saves are fast at all, "because in the past with one insert/update per line a simple workflow could take very very long" — so the write path was measured rather than extrapolated (see below). At the measured ≈27,000 rules a second the ceiling is about seven seconds of writing, which is what the rationale in `Services::WriteBudget` now says instead of an extrapolation. |

## Decided (autonomous) — 2026-08-29, the write path measured

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | Whether a bulk save is fast enough to leave as it is | **Yes, and it is now measured rather than argued** | Redmine 7.0 / PostgreSQL 16, in the development container. A matrix save is **~8 statements per project and flat** — 5 projects and 50 projects both cost 8.0/project — and about **27,000 workflow rules a second**, flat from 4,860 to 172,800 rules. The contrast, on the same 1,620 rules: the writer takes **30 statements and 0.22 s**, one `save` per rule takes **6,480 statements and 5.03 s**. That is the shape Jan remembered being slow, and it is the shape the writers exist to avoid. *Empty this workflow* and *Return to the generic workflow* are 5 and 6 statements in total for 1,000 combinations. The numbers are in `docs/design.md`, the README and `docs/STATE.md`. |
| 2026-08-29 | The Save button's confirmation threshold | **Its own setting, `bulk_save_confirm_threshold`, defaulting to 5,000 — not the row and column actions' 50** | Sharing one threshold was WP13's own doing and the measurement showed it was wrong: at 50 rules the dialog fired on essentially **every** multi-workflow save, because two workflows of a six-status matrix is already 216 rules. A dialog that always appears carries no information and becomes something to click through, which is worse than not having one. The two are not the same kind of surprise: a row or column action is one click whose effect is not visible until you look, while a Save is a form the operator has just filled in on a page that already says how many workflows a cell stands for. 5,000 is roughly 46 workflows of a six-status matrix, and `plugin_conventions_spec.rb` now asserts the three defaults are in increasing order, because they only make sense as a scale. |

## Decided (Jan) — 2026-08-29, *give own workflow* in bulk

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | *Give own workflow* is the one bulk action written a row at a time, and it is not covered by any ceiling. A ceiling (**B**), a batched rewrite (**C**), or nothing (**A**)? | **B and C together — "write down and build as recommended"** | Asked after the action was measured rather than argued, and asked again by Jan in the form "can we do C and still guard two administrators at once, maybe with optimistic locking?" — which is the question that produced the answer's shape. Optimistic locking (`lock_version`) is the wrong tool: it protects one existing row from two concurrent *updates*, and this race is two concurrent *inserts*, already arbitrated by the unique index. What the per-row write actually provided was **attribution** — which rows *this* request created — and what replaces it is the coordination rows WP13 built, taken for the (tracker, role) pairs, which is trackers × roles rows and never per project. **ADR-004** carries the whole argument, the measurements and the rejected alternatives. Measured after building it: 20,000 combinations and 600,000 rules went from 110 s (294 s in a second sample) to **18 s** on PostgreSQL and from 99 s to **14 s** on MariaDB, in 151 statements rather than 60,042; the *empty* variant from 60 s to 3.9 s. The ceiling is `bulk_write_ceiling`, the setting the matrix save already uses, which now means about the same wall clock on both screens — an equivalence that is only true because of the batching. |
| 2026-08-29 | What happens when a scope row appears under a batched insert anyway — the two paths that do not take the lock (duplicating a tracker or role, copying a project) | **Raise, roll back and let the administrator press it again; never skip** | `insert_all!` rather than `insert_all`. Both paths act only on records that have just been created, so a collision needs a project or tracker created between one administrator opening the screen and another pressing Save. A rollback that says so beats the silent miscount 0.1.1 shipped, and with the lock held a conflict is a defect worth hearing about rather than a race to absorb. |
| 2026-08-29 | Whether the ceiling should count combinations or workflow rules | **Workflow rules, and the same setting as the matrix save** | On the per-row path it would have had to be combinations: the *empty* variant writes no rules and still took a minute, so a rules-based number would not have bounded it. Batched, the empty variant is 3.9 s at 20,000 and needs no bound at all, which is what lets the two screens share one number in one unit. The plugin gains no fourth setting. |

## Decided (autonomous) — 2026-08-29, WP15's test debt

| Date | Question | Decision | Why |
|---|---|---|---|
| 2026-08-29 | What a "neighbour coexistence" gate can honestly assert, given that a neighbour aliasing a method this plugin has *prepended* recurses forever | **The two load orders a running process can build, plus the asymmetry the plugin actually has** | A module already prepended cannot be pushed back down a chain, so "a neighbour prepends before us" is not constructible at spec time — and it is the harmless case anyway, two prepends composing through `super` in either order. What the file builds instead is a neighbour that prepends *after* (above us) and one that alias-chains *before* (below us, in the class itself), which between them cover both idioms on both sides. The third combination — an alias chain over a prepend — is infinite recursion in Ruby, is every prepending Redmine plugin's exposure, and is the neighbour's own deprecated idiom; where this plugin has a choice is core's **helper modules**, and both of those now have a behavioural gate rather than only `ProjectsHelper`. |
| 2026-08-29 | That most patch methods do not call `super`, so a neighbour underneath them is silently bypassed | **Asserted as a stated property, not treated as a defect** | It follows from the decision of 2026-08-26: core's own queries carry no `project_id` predicate, so for an inheriting project `super` would read every other project's rows (INV-4). There is no `super` that answers correctly and therefore no fix. What the gate can do is make the consequence explicit — an installation combining this plugin with one that filters the same method by aliasing first will find its filter ignored — and pin `Project#copy`, which *does* delegate, as the contrast. Worth knowing before a support question rather than during one. |
| 2026-08-29 | Whether the authorization matrix should assert a status per action or a shared expectation | **A table over every action × every visitor, with a last example that asks the router which actions exist** | `#transitions` and `#enable` had six angles each; `#permissions`, `#graph`, `#inherit` and `#clear` had none. Per-action prose examples are how that gap arose and would arise again. A table shows the uniformity at a glance, and the router example makes an action added without a row a failure rather than an omission. |
| 2026-08-29 | Where the 500-term `OR` delete gets measured | **In the suite, at exactly `DELETE_BATCH_SIZE` and one over it, on whatever database is running** | PostgreSQL was measured safe to a thousand nested `OR`s during the audit; MySQL and MariaDB — six of the nine cells — were unmeasured, and nothing in the suite had ever built more than a handful of terms. A benchmark run once answers for the host it ran on; an example answers on every cell, every push. MariaDB 10.11 plans it without complaint. |
| 2026-08-29 | What a downgrade costs, discovered by rehearsing it | **Every project workflow, and every own *empty* decision — stated rather than left to be found** | `VERSION=0` is not the reverse of an upgrade. Migration 001's `down` deletes every rule that names a project on purpose: without it, dropping the column turns every project's rules into rules of the workflow every project shares, which is the worst silent widening available. And an own *empty* decision has no rules to be reconstructed from, so it does not come back. Both sentences are now checked by `dev/check-upgrade.sh` on all nine cells, and both belong at the top of WP16's downgrade procedure. |
| 2026-08-29 | Whether to keep two examples that cannot be made red | **Keep them, and say so in the file** | The reload-guard pair asserts that re-running `apply_patches` moves nothing — which `Module#prepend` already guarantees, so emptying `prepend_once`'s guard changes nothing an example can see. They are forward gates against an `apply_patches` that stops being idempotent (a fresh anonymous module per call, an `include` where a `prepend` was), which would grow the chain only on a host that reloads and never on CI. A gate with no teeth today is worth keeping only if it says so; this one does. |

## Answered, kept for the record — the measurement behind the decision above (2026-08-29)

- **Choice:** *Give own workflow* is the one bulk action still measured **per
  combination**, and it is not covered by any ceiling. **Measured on 2026-08-29**,
  after the question was asked, on Redmine 7.0 with PostgreSQL 16 and MariaDB
  10.11 in this container. Every figure is one scenario per process, in its own
  transaction, because a first pass that ran them all inside one transaction
  measured the accumulated undo of the earlier ones rather than the work.

  The shape: 500 projects × 5 trackers × 8 roles = **20,000 combinations**, a
  shared workflow of 30 transitions per (tracker, role), so **600,000 rule rows**
  to copy.

  | what | PostgreSQL 16 | MariaDB 10.11 |
  | --- | --- | --- |
  | today, copy of the shared workflow | **110 s** and **294 s** in two samples, 60,042 statements | **99 s**, 60,048 statements |
  | batched prototype, same work | **28 s**, 105 statements | **23 s**, 105 statements |
  | today, own *empty* workflow (no copy) | **60 s**, 40,042 statements | **47 s**, 40,048 statements |
  | batched, own *empty* workflow | **3.4 s**, 104 statements | **2.8 s**, 104 statements |

  At a more ordinary 200 projects × 3 trackers × 4 roles (2,400 combinations,
  72,000 rules): today 13.2 s (PG) / 9.6 s (MariaDB); batched 3.2 s / 2.2 s.

  **What the measurement settles, and it is not what the question assumed:**

  1. **Batching is possible and portable.** `insert_all!` for the decisions plus
     one `INSERT … SELECT` per 1,000 projects, joining the shared rules to the
     scope rows just created, runs on both adapters and produces **identical**
     scope and rule counts to the per-row path. Statements fall from ~60,000 to
     ~105.
  2. **It does not make the large case fast.** 28 s (PG) / 23 s (MariaDB) is
     still past what a front-end proxy will wait for. The remaining time is the
     **data**: 600,000 rows at roughly 21,000 rows a second, which is the same
     throughput the matrix writer already measures. No amount of batching removes
     it. **So a ceiling is needed whether or not the write is batched.**
  3. **It does make the *empty* variant free** — 3.4 s for 20,000 combinations,
     from 60 s. There the cost was **entirely** round trips.
  4. **The per-row path is not linear and not stable.** 5.5 ms per combination at
     2,400 but 14.7 ms at 20,000 in one sample and 5.5 ms in another — a factor of
     2.7 between two runs of the same thing, because it holds a transaction open
     for minutes and pays for whatever else the database is doing. The batched
     path is flat at 1.4 ms (PG) / 1.2 ms (MariaDB) per combination in every run.
     **Predictability is what makes a ceiling mean anything.**
  5. **A suspicion raised in passing was wrong and is retracted here.** The OR-of-
     500-triples delete that `ScopeWriter` uses looked, in the first dirty probe,
     like a MariaDB pathology (4.2 s for 500 triples). Measured clean it is
     **0.05 ms per combination on both adapters** — the 4.2 s was the probe's own
     700,000-row open transaction. This also answers part of WP15's item 4:
     `DELETE_BATCH_SIZE` at 500 terms is fine on PostgreSQL and MariaDB.

- **Options, restated against the numbers:**
  **A) Nothing.** A large selection is 1.5–5 minutes and a timeout that rolls
  everything back. **B) A ceiling only.** Closes the hazard, needs no ADR — but
  on the per-row path the cost per combination varies threefold with size, so the
  number has to be conservative (a 10-second budget is roughly 2,000
  combinations), and it has to be counted in *combinations* rather than in
  workflow rules, because the *empty* variant writes no rules and still takes 60 s.
  **C) Batch it, with the ceiling.** Needs the ADR you named. The decisions go in
  one `insert_all!` per 1,000 rows and the rules in one `INSERT … SELECT` per
  1,000 projects, under the coordination rows WP13 already built — locked for
  (rule\_type, tracker, role), which is trackers × roles rows and never per
  project. Then the cost is linear, the *empty* variant is instant, and the
  ceiling can be counted in **workflow rules** and share `bulk_write_ceiling`
  with the matrix save, where 200,000 rules means about the same wall clock on
  both screens.
- **Recommendation: C together with B** — because B alone forces an awkward unit
  and a small, conservative number, while C makes the rules-based ceiling correct
  and gives the *empty* variant back as the safe bulk action. If only one lands
  now, land B.
- **Two things C also fixes, which the question did not ask about:** the 20,000
  copies currently run **holding no lock on the workflow being copied**, so a
  concurrent save of the shared workflow gives earlier projects the old rules and
  later ones the new rules, silently; and 60,000 round trips inside one
  transaction is what makes the timing unpredictable.
- **The one loose end C carries:** two other paths create scope rows without that
  lock — duplicating a tracker or role, and copying a project — and both act only
  on records that were just created, so a collision is very unlikely but needs a
  chosen behaviour: raise and let the administrator retry, or have those paths
  take the same lock. Recommendation: raise, because a rollback that says so
  beats a silent miscount.
- **Urgent?** no. Nothing is blocked and the action is correct at every size; it
  is slow at a size nobody is running. But the number in the earlier version of
  this entry ("about 5 ms per combination, roughly 100 seconds") was optimistic:
  a clean run of the same thing took **294 seconds** once.

## Decided (autonomous) — 2026-08-29, WP16 items 2-4: the backup-aware uninstall

All Class A unless it says otherwise.

- **The uninstall ships a backup rather than a warning.** WP15 established that
  `VERSION=0` discards every project workflow on purpose; a downgrade procedure
  whose first sentence is "there is no way back" is not a procedure. So the
  plugin now exports the population the migrations destroy, and restores it.
- **The file is JSON, not YAML.** Reading a backup is `JSON.parse`, which builds
  no objects. `YAML.load` of a file an operator was told to keep somewhere safe
  is a much larger promise, and `safe_load` would only move the question.
- **A restore goes through the writers, not around them (INV-2).** A backup file
  is data of unknown age from outside the application, so the whitelist that
  stands between a request and the `workflows` table stands between the file and
  it too. A status, tracker or custom field deleted since the export is refused
  there and counted in the report. The cost is one writer call per (project,
  tracker, role, rule type) — a restore is a maintenance task run once, not a
  request path — and the *scope* creation is grouped, one lock per (tracker,
  role), because that half is what a five-hundred-project restore would have
  felt.
- **The backup holds decisions, not only rules.** An own *empty* workflow is a
  scope row with nothing under it, and it is the one thing a downgrade loses
  without leaving a trace. A backup of rules alone would come back as
  inheritance, which is the exact confusion INV-3 exists to prevent.
- **The generic workflow is not in the file.** Nothing in these migrations puts
  a `project_id IS NULL` row at risk, and restoring one would be a generic write
  — which INV-1 says a project restore must never be.
- **A restore leaves alone any combination that already has a decision**, and
  says how many. `OVERWRITE=1` replaces the rules and keeps the decision and its
  author (INV-3's third action), rather than deleting the scope and re-creating
  it, which would move `created_by_id`. **Class B**, and the safest reversible
  default: on the expected path — a database whose plugin data was just thrown
  away — there is nothing to leave alone and the default costs nothing.
- **A restore keeps the audit trail.** Stamping whoever ran the rake task would
  answer "who decided this project runs its own workflow" wrongly for every
  project at once. A user deleted since the export leaves the column null, which
  is what the column already means.
- **Duplicate rows come back as one.** The payload the writers take is a matrix
  and a matrix has one cell. This is the same repair the deduplication task
  performs and it cannot change what a workflow permits; it is written down
  because it is the one way a restore is not byte-for-byte.
- **The uninstall's order is the safety property, and a spec pins it**: count,
  say, ask, write the backup *and read it back*, then migrate. A run refused at
  the confirmation writes no file, so a forgotten `CONFIRM=yes` does not leave a
  half-finished backup in the way of the next attempt.
- **`CONFIRM=yes` is typed in full and never defaulted**, and `SKIP_BACKUP=1`
  exists for an operator with a database dump — not as the default, and it says
  so on the way past.
- **The rake task bodies live in `lib/redmine_project_workflows/tasks.rb`**, not
  in the `.rake` file: RuboCop does not inspect `.rake` files and neither can a
  spec load one usefully. The two cops that then object — `Rails/Output` and
  `Rails/Exit` — are excluded for that one file with the reason, because a rake
  task's user interface *is* its standard output and its refusal *is* a non-zero
  exit.
- **`dev/check-uninstall.sh` checks the output of the refusal, not only its exit
  status.** The first version passed on a host the working tree had never been
  synced into, where the task did not exist and rake exited non-zero for that
  reason instead.
- **The alpha warning stays.** `docs/release-criteria.md` answers all thirteen
  criteria for 0.1.6: three are unmet, and one of them — "has run on a real
  installation, with real data, for a stated period" — is not something this
  repository can answer. Removing the warning is a claim about production
  installations and is Jan's to make.

## Decided (autonomous) — 2026-08-29, WP16 item 1: the rehearsal from a real release

- **`origin/main` is the ref, and a tag is not a precondition.** The earlier
  entry said this item was blocked on tagging 0.0.3. It was not: what a
  rehearsal needs is a ref it can check out that does not move, and `main` is a
  branch **no session writes to** — `CLAUDE.md` pins every session to
  `claude/dev` and `docs/review/README.md` repeats it for findings. A tag is
  still better, because it cannot move at all, so
  `dev/check-release-upgrade.sh` takes the ref as its first argument and
  `docs/release-criteria.md` says to point it at the tag once one exists.
- **The rehearsal runs the released version's own code, and that is the point.**
  Every other migration check seeds its data with today's models, which is the
  one thing a real upgrade never does. This one installs the plugin at the ref,
  writes project rules through *that release's* writers, and asks *that
  release's* `Issue#new_statuses_allowed_to` and `#required_attribute_names`
  what an issue may do — then upgrades and asks again.
- **It fails if its two projects answer the same thing before the upgrade.**
  One project overrides and one inherits; if those two answers were equal, the
  comparison afterwards would hold whatever the resolver did. The first version
  of the script did exactly that for a different reason (below) and reported a
  backfill failure instead of a seeding one.
- **It checks that the released writers wrote anything at all.** The first
  version lost every project rule to a shell quoting mistake — `'"'"'` is the
  escape for a single quote inside a *single*-quoted string, and inside the
  double-quoted `rails runner "…"` argument it ends the string — and then
  reported, truthfully, that the backfill had produced nothing. A gate whose
  premise is not checked reports on the wrong thing.
- **It rebuilds the host's test database itself**, unlike the other four checks,
  which require a stock database as a precondition. It has to start from one that
  has never seen migrations 004-007, and there is no way to ask for that as a
  precondition without every caller doing it.
- **Nothing in the plugin changed for this item.** The result is that the
  0.0.3 → 0.1.6 upgrade is now a measured claim rather than a believed one: the
  same statuses, the same required fields, not one rule row touched, and a scope
  for exactly the combinations that had rules.

## Decided (Jan) — 2026-08-29, the compatibility write policy

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | A second ChatGPT review asked for workflow **writes to be refused** on a host whose Redmine has drifted or cannot be measured, until an administrator acknowledges the exact version and digest set. ADR-002 had already answered "warn, never refuse" — but the review's proposal is a genuinely different third option rather than a re-run of the argument: Redmine still boots, reads still work, and the diagnostics page stays open, so the objection that a refusal bricks an installation mid-upgrade does not apply to it. | **A — warn and continue** | ADR-002 stands unchanged. What the finding is really about is *where* the warning is: a `:drifted` or `:unmeasured` host announces itself in the application log and on a diagnostics page nobody has to visit, and says nothing on the screens where somebody is about to change workflow rules. WP19 puts a persistent banner there. Reversing this later is a policy change in one place, and option B is written down here so it does not have to be re-derived. |

## Decided (autonomous) — 2026-08-29, the revalidation plan

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | How to fix an interrupted restore | **Per-combination transactions, not one transaction around the whole restore** | Both give all-or-nothing. The per-combination shape makes a completed combination genuinely safe to skip, which is what turns the documented retry from a trap into a recovery — and it avoids holding a lock for the length of a restore of every project on the installation. The external review reached the same conclusion independently and it is the shape every other writer in this plugin already uses. |
| 2026-08-29 | How to close the gap between a backup's export and the migration reversal that destroys what it copied | **A monotonic revision the write coordinator bumps, not a lock over the whole operation** | Locking every workflow for the length of an operator's confirmation prompt is the obvious answer and the wrong one: the prompt is unbounded. A counter carried in the backup and re-checked immediately before the migrations run is cheap, durable, and refuses rather than destroying. It also gives stale-form detection later, for free. |
| 2026-08-29 | Whether the four SQLite spec failures are a defect | **No — a missing adapter guard** | SQLite is not one of the nine supported cells and `spec/spec_helper.rb` says so. The batching examples build a 500-term OR that SQLite's parser cannot take, and the file's own header says as much without guarding for it, while nine concurrency examples in the same suite already skip on the same kind of question. It costs a developer on a SQLite host four red examples and nothing else. |
| 2026-08-29 | What the two reviews disagree about, and which is right | **The runtime is sound; the recovery tooling is not** | The external review answered "NOT READY" for the whole plugin. That is too coarse: authorization, INV-1, INV-3, the ceiling and the write lock were all measured correct this run, and they are what every user touches. The defects are in a rake task an administrator starts deliberately. It still blocks a release, because it is the tooling the uninstall procedure rests on — but the distinction is what makes WP17 a four-item package rather than a rewrite. |

## Decided (autonomous) — 2026-08-29, WP17 as it was actually built

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | The stale-backup guard, revised from the plan's own entry above | **Re-read and compare, not a monotonic revision column** | The plan chose a counter the write coordinator bumps, carried in the backup and re-checked before the migrations run. Building it turned up a strictly better answer that needs no schema at all: the uninstall already holds the document it exported, so it re-exports immediately before reversing anything and compares the two. It is **exact** where a counter is approximate, it needs no migration (and therefore no new obligation under INV-8), and it costs one extra pass of two SELECTs during an operation that runs once. The counter's one advantage — detecting staleness of a file written days ago — is not what this window is about, and a file that old is refused for a better reason: its projects, trackers and statuses are checked against the ones that exist now. |
| 2026-08-29 | Whether a restore that could not put a combination back should exit non-zero | **Yes** | An operator reading a terminal sees the named failures either way. A restore is the thing that runs unattended — an installer, a container entrypoint, a colleague's script after a database restore — and a silent zero there is how a half-restored installation gets declared finished. |
| 2026-08-29 | How to ask an adapter whether it will give an isolation level | **Ask for the level and catch the refusal; never `supports_transaction_isolation?`** | SQLite answers that predicate with **true** and then refuses every level but `read_uncommitted`, so the check that reads like the careful one is the one that raises. And the catch has to be a *retry* rather than a resume: Rails begins a transaction lazily, so on Rails 6.1 the refusal arrives from inside the block, not from the `transaction` call. A `began` flag written to avoid running the block twice made the fallback unreachable; `dev/check-uninstall.sh` caught it, the suite did not, and the block is two SELECTs so running it twice is free. |
| 2026-08-29 | Fixing F06 (the SQLite batching skips) inside WP17 rather than WP19 | **Yes, taken along** | The guard it needs is the same predicate WP17's own two-connection backup example needed — `supported_adapter?` in `spec/spec_helper.rb` — and leaving it for later meant four red examples on every local run in between, which is how a suite stops being read. |

## Decided (autonomous) — 2026-08-29, WP18

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | Where the one resolver lives | **A service, not a controller mixin** | The four resolvers it replaces were three mixins and a private controller method, so a fifth mixin would have been the same shape of thing. `Services::ExactSelection` can be driven directly by a spec with a list and a parameter, which is what made sixteen shape examples cheap; the controller examples then assert the one thing only a controller can, that nothing was written. |
| 2026-08-29 | The copy screen's target roles now resolve against the list the form offers | **Tightened deliberately** | Core's body was `Role.where(id: ...)`, which resolves a role that takes no part in a workflow — one the form does not list. Copying to it writes rules nothing reads. Reaching it needs a hand-built request or a form rendered before the role's permissions changed; either way, refusing is the answer the rest of the plugin gives. |
| 2026-08-29 | A matrix selection now comes back in candidate order | **Accepted** | Core returned `where(id: ids).to_a`, which is the database's order, so two requests naming the same two trackers could draw them in two orders. The candidates are the sorted list the screen already renders. Visible only as a more stable ordering. |
| 2026-08-29 | Renaming `invalid_project_selection?` to `invalid_selection?` | **Yes** | It now covers every selector on the screen — projects, trackers, roles — and the old name would have said it covered one. Six call sites, all in one controller. |

## Decided (autonomous) — 2026-08-29, WP19

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | Where the compatibility banner is rendered from | **Seven explicit calls, and a spec that drives all seven** | A single insertion point would have been the action-menu partial, but that emits a floated `div.contextual` and a full-width warning box cannot go inside it without bespoke CSS, which the repo does not do. So the call is one line after the title of each screen, and `spec/views/compatibility_banner_spec.rb` is what makes it unforgettable: a screen added later without the banner fails there rather than being noticed on a drifted host. Same shape as the Deface override spec and INV-9. |
| 2026-08-29 | Whether the banner links to the diagnostics page for everybody | **Administrators only** | The page requires an administrator. A project manager who followed the link would get a 403, which tells them less than the sentence already did. They get the sentence. |
| 2026-08-29 | Which icon the diagnostics link carries | **`help`** | Verified present in the 6.1 and 7.0 sprite sheets (fetched and grepped) and defined as `.icon-help` in 5.1's stylesheet. A sprite name that does not exist renders an invisible icon and says nothing, which is the same silence INV-9 is about. |
| 2026-08-29 | Reading the backup file back before the rename rather than after | **Before** | A file that does not parse must never become the backup. The uninstall task's own read-back is then a second opinion rather than the only one. |

## Decided (Jan) — 2026-08-29, the README notice and the review archive

| Date | Question | Answer | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | The README opened with *WARNING: alpha stage, do not use in production!* `docs/release-criteria.md` treated removing it as a claim only Jan could make (A3), and every session recommended leaving it. | **Neither A nor B: reword it.** | Jan asked for a notice that makes somebody installing it *aware* that the plugin is fairly new and not yet tested in a wide range of production environments — rather than telling them not to use it. The notice now says what is tested (three Redmines × three databases, every push, 1,300+ examples), what is not (a wide range of real installations), why it matters (workflow rules are authorization), and what to do about it (try it on a copy, take a backup, read the surprises list). A1..A4 are unchanged and still govern removing the notice altogether; only the wording moved. |
| 2026-08-29 | Whether the two ChatGPT reviews get files of their own | **Yes, as archives — not as findings files** | Jan asked for it. It does not reverse the decision of 2026-08-28 below ("no findings file of its own"): neither `2026-08-28-chatgpt.md` nor `2026-08-29-chatgpt.md` carries a `Status:` line and nothing is acted on from them. They exist for the reason `2026-08-25-external.md` and `2026-08-26-codex.md` do — so a later reader can see what was claimed as well as what was concluded. Each carries a header mapping its items to the findings file that answered them, and naming the places this repository disagreed. |

## Decided (autonomous) — 2026-08-29, the browser run

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | Whether the browser scenarios become a CI gate | **No — `dev/e2e/`, run by hand** | They need a running server with seeded data, which CI does not build, and standing that up on nine cells would multiply the matrix's cost for a check that is about what a person *sees*. They belong with `dev/`'s other reproduction tooling: run them when something a person looks at has changed, and put the result in the session report. |
| 2026-08-29 | The one nit the browser run found | **Reported, not fixed** | `CLAUDE.md`: "a defect you notice outside the work package you are on goes into the session report and, if it is real, into a findings file — not into the diff." It is a one-line view change and the correct form is already documented in the neighbouring partial, so it is cheap whenever somebody wants it — but WP17..WP19 are closed and this is not theirs. |

| 2026-08-29 | The nit the browser run found, after Jan asked for it to be fixed | **Fixed on both screens, not only the one the finding named** | The inventory had the identical construction and therefore the identical defect. A fix that left the sibling screen inconsistent would have been half a fix, and the next reviewer would have filed it again. |

## Decided (autonomous) — 2026-08-29, the documentation split

| Date | Subject | Decision | Notes |
| --- | --- | --- | --- |
| 2026-08-29 | The README was 858 lines | **Split: a short README plus five documents under `docs/`** | Jan asked for a README a Redmine administrator can actually read — short, professional, complete but not exhaustive — with the depth moved out. The README now covers what it is, what you get, requirements, install, a five-step start, the one rule that matters and where everything else is. `usage.md`, `gotchas.md`, `settings.md`, `operations.md` and `compatibility.md` hold the rest. |
| 2026-08-29 | Which word the documentation uses for the workflow every project shares | **"generic", matching the screens** | The first draft said "shared", which reads better in prose but appears nowhere in the interface, so a reader would look for it and not find it. The README introduces the term once — "shared by every project — the *generic* workflow" — and uses the screens' word from then on. |
| 2026-08-29 | Where the A4 list of surprising behaviours went | **`docs/gotchas.md`, linked from the install notice and the documentation table** | It was a README section and a release criterion depends on it being "written down where somebody installing it will read them". A link from the notice at the top satisfies that better than a section most readers scroll past. `docs/release-criteria.md` now points at the new file. |
| 2026-08-29 | Screenshots | **Seven, committed under `docs/images/`, reproducible** | About 570 KB in total, cropped to the content rather than full pages. `dev/e2e/seed_docs.rb` and `dev/e2e/docshots.mjs` regenerate them, because an illustration nobody can reproduce goes stale silently. The workflow it draws is a plain path with two shortcuts: Redmine's default everything-to-everything workflow draws as spaghetti and illustrates nothing. |

| 2026-08-29 | Colour in the workflow diagram, asked for by Jan | **Two fixed accents, on top of the line style — never instead of it** | The drawing was `currentColor` throughout, argued at the top of `ProjectWorkflowGraphsHelper`: a theme changes exactly the colours a diagram would hard-code, and a black stroke on a dark theme is invisible. That argument is about colour as the *only* signal. Line style and the legend still carry the meaning, so the picture reads the same in greyscale; colour is added so a dashed arrow can be picked out of a crowded drawing without tracing it. Ordinary arrows and every box stay `currentColor`, so a theme still owns most of it. The two accents (`#2E86C1`, `#C0651A`) are fixed because a plugin shipping no stylesheet cannot read the theme, and they were *measured* — both clear WCAG 1.4.11's 3:1 against `#ffffff`, `#f6f6f6`, `#1e1e1e` and `#2b2b2b`, with the numbers in the source. Verified in a browser on a simulated dark theme as well as a light one. |
