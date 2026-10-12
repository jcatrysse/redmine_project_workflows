# Decided by Jan, 2026-10-07

Jan Catrysse answered the open questions of this plugin on 2026-10-07, one at a time, with the
options, an explanation and the recommendation in front of him, in the coordinating session that
started the migration sessions (https://claude.ai/code/session_01GiSsYPm3bxvqrpZkdCxNoi).
This file records his answers as given; his free-text notes are quoted verbatim. The migration
session moves each into docs/REDMINE7-MIGRATION.md as decided and builds what it requires.

General decisions by Jan (2026-10-07), for every GEOxyz plugin:
- GEOxyz goes straight to Redmine 7: no backports to 5.1. Nothing is cherry-picked to the default branch or to the branch production runs today; `redmine70-migration` is what goes live with Redmine 7. Redmine 5.1 compatibility is no longer a requirement; drop that rule from the plan and do not add code paths that exist only for 5.1.
- GEOxyz does not use MariaDB or MySQL; production runs PostgreSQL 16. Run the tests and the e2e set on PostgreSQL only. Keep SQL portable where that costs nothing, but MariaDB runs are no longer required and a MariaDB-only problem is a note in the plan, not a blocker.
- A plugin that depends on deface requires it without a version constraint (change it when the Gemfile is touched anyway).
- A Redmine core method that other installed plugins also patch is patched with `prepend`, never with `alias_method`. Mixing both on one method recurses; that is what made Project > Settings return HTTP 500 with all GEOxyz plugins installed. Check this plugin: if it patches such a method with `alias_method`, switch it to `prepend` with a test, and confirm Project > Settings, the issue list and an issue page answer 200 with the other GEOxyz plugins installed (`RMP_EXTRA_PLUGINS`).
- GitHub Actions stay manual only (`workflow_dispatch`).

Decisions for this plugin:
1. redmine_project_workflows-q1: Blijven de automatische testen van deze plugin bij elke wijziging op GitHub draaien?
   Jan chose B: "Alleen handmatig, zoals de andere GEOxyz-plugins" (Volgt de afspraak, maar fouten vallen pas op als iemand de testen zelf start.). Carry this out (see step 3).
2. redmine_project_workflows-q2: Maken we van het vragen van 'deface' zonder versielimiet een vaste afspraak voor alle plugins?
   Jan chose B: "Aanvaarden plus afspraak voor alle GEOxyz-plugins" (Elke GEOxyz-plugin vraagt deface voortaan zonder versie of met dezelfde beveiliging, telkens wanneer zijn Gemfile toch aangepast wordt.). Carry this out (see step 3).
3. redmine_project_workflows-q3: Herstellen we dat Impact en Urgency wegvallen uit de veldrechten van workflows?
   Jan chose A: "Apart herstellen, met eigen tests" (Een aparte wijziging laat beide plugins samen werken op dat scherm, maar raakt gevoelige code van deze plugin.). Carry this out (see step 3).

For q1: change the workflows in .github/workflows so they only run on `workflow_dispatch` (remove the push, pull_request and schedule triggers), as Jan decided for every GEOxyz plugin. For q2: record the deface rule; this session owns writing it down as the general rule. For q3: the fix may live in this plugin or in redmine_itil_priority; fix it where the cause is, with a test, and say which.

What to do:
1. `git fetch && git checkout redmine70-migration && git pull`.
2. Record every decision above in docs/REDMINE7-MIGRATION.md: move it from open to decided, with the choice, the date 2026-10-07 and Jan's note verbatim where there is one. Update the plan's rules for the general decisions (no 5.1, PostgreSQL only).
3. Carry out each decision that needs a change: one commit per decision, each with a test that fails without it. A choice that says "later" or "separate change" is built now, in its own commit. A choice that says it happens after the upgrade goes under "After the upgrade". A decision that needs no code (not reporting to a vendor, accepting a loss, a role setting) is only recorded.
4. Plugin tests green on Redmine 7.0-stable-GEOxyz with PostgreSQL, alone and with the other GEOxyz plugins installed. Quote the numbers.
5. `./.codex/start_server.sh` and `./.codex/e2e.sh`: a scenario for every function a decision touches, as admin, manager, reporter and outsider, including the refusal paths. Open every screenshot, commit them in docs/e2e/ and list them in the inventory.
6. Your own adversarial review of the new commits, then `./.codex/openai_review.sh` when OPENAI_API_KEY is set; every finding gets a Resolution line. Without the key, say the review was skipped.
7. Update Status, the inventory, the work list and "After the upgrade". Push `redmine70-migration` after every commit.
8. These decisions are final; do not stop to ask about them. If one turns out to be impossible, write down why in the plan and carry on with the rest.
9. End with a short report in Dutch: per decision what you did (commit), test numbers, e2e numbers (scenarios, screenshots, problems), the review result, what is left for Jan.

## Round 2, decided by Jan on 2026-10-07 (evening)

Jan answered these follow-up questions from the migration report the same way, one at a time, in the coordinating session.

- redmine_project_workflows-n2-1 (proj_wf 4): Neemt een project een eigen workflow, dan neemt het de algemene regels voor Impact en Urgentie mee. Die velden staan niet op de projectschermen van deze plugin, dus per project aanpassen kan niet. Wat doen we?
  Jan chose: "Zo laten" (Projecten volgen de algemene regel; bouwen pas als een project een eigen regel nodig heeft.). Already built: keep it and record the decision.

## Round 6, 2026-10-12: Impact/Urgency per project

Jan answered the open question "Impact/Urgency per project" after an impact analysis in the coordinating session: **build it, in this plugin, as a generic extension point** (not as a hook inside redmine_itil_priority).

What the analysis found (verify it, do not take it on trust):
- Enforcement already works: a project's own WorkflowPermission rows for `impact_id` / `urgency_id` are copied on takeover (`ScopeWriter.enable`, `copy_generic: true`) and enforced; `PermissionWriter` accepts the names through `WorkflowPermission#validate_field_name` (C2, `a080401`), and `delete_permissions_for_scope` deletes only the submitted (status, field) cells, so saving a project matrix does not drop them.
- What is missing is the row list: `ProjectWorkflowsController#permissions` and `ProjectWorkflowRulesController#permissions` build `@fields` from `Tracker::CORE_FIELDS_ALL` minus disabled core fields, and `ProjectWorkflowsController#update_permissions` builds `@offered_field_names` the same way, so a neighbour's fields are never offered and a difference on them is reported as not shown.
- redmine_itil_priority adds its two rows to core's screen by prepending `WorkflowsController#default_render` (`lib/redmine_itil_priority/patches/workflow_patch.rb`, `FIELDS = %w[impact_id urgency_id]`).

What to build:
- A small, documented extension point in this plugin through which another plugin's field-permission fields appear on the project matrix, the administration rule matrix and in `@offered_field_names`, with their label. One list, used by all three places. Choose the design yourself (Class A within your invariants): for instance a registry other plugins call, or offering the extra names core's own Fields permissions screen shows. If a registration call in redmine_itil_priority is needed, write it down exactly; the coordinating session puts it in that plugin's branch.
- INV-1 to INV-9 hold. INV-2 in particular: every offered name must still pass the writer's whitelist and the model's own `validate_field_name`; a name that a plugin registers but the model refuses is not written.
- Tests that fail without it: Impact/Urgency rows shown on both project matrices with redmine_itil_priority installed; a project-scoped impact rule saved and enforced in that project only, the generic rule and other projects untouched; nothing offered without a neighbour plugin; the comparison after a save no longer reports those fields as not shown.
- e2e with redmine_itil_priority: a project manager sets Impact read-only for one project, a member of that project cannot change it, a member of another project still follows the generic rule; screenshots opened and committed.
- Update the plan (open question to decided, "After the upgrade"), this plugin's docs/DECISIONS.md, your own review and `./.codex/openai_review.sh` when OPENAI_API_KEY is set; push after every commit; end with a short Dutch report.
