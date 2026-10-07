# Redmine 7 migration: redmine_project_workflows

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL and MariaDB, every function exercised end to end on a real running Redmine in a
> browser (with and without permissions, failure paths included) with screenshots you looked at,
> and an OpenAI review of the diff when OPENAI_API_KEY is set. Report to me in Dutch at the end.

This file is the plan and the memory of that work. Update it as you go: verdicts, results,
what is left. Written 2026-10-06 from a measured analysis (report at the bottom).

## Status

| | |
|---|---|
| Plugin id | `redmine_project_workflows` |
| GEOxyz runs today | `main` |
| Upstream | geen (eigen plugin) |
| Runs on Redmine 7 as is | JA (branch `redmine70-migration`, 0.1.6 line); naast andere plugins waren fixes nodig (C1, C2) |
| Upstream sync | GEEN UPSTREAM |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 1 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz `8067e23`), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16.15 and MariaDB 10.11.14 |
| Migration session | 2026-10-06, done; Jan's decisions built 2026-10-07 (see "Decided by Jan") |

## Already on this branch

- `d98de23` Render the multiselect toggle icon on Redmine 6+
- `4633811` Merge claude/dev (0.1.6) into redmine70-migration

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Open items from the analysis** (Dutch; where they conflict with a decision or a priority item above, those win)

1. Decide whether claude/dev (0.1.6 rewrite, 210 commits ahead of main, own CI incl. 7.0) replaces main
   - **Verdict: decided by Jan** (coordinator addendum below): GEOxyz moves to the 0.1.6 line; this
     branch carries it. The upgrade from `main` was rehearsed (`dev/check-release-upgrade.sh origin/main`,
     green on both databases).
2. claude/dev boots, migrates (001-006, rollback OK) and smokes 72/72 on R7; its rspec could not run in the harness (rspec-rails removed from plugin Gemfile)
   - **Verdict: done.** rspec runs through `dev/setup.sh`/`dev/run.sh`, which put rspec-rails in the
     host's `Gemfile.local` (kept that way). Migrations are 001-**007** on this branch.
3. Optionally pin deface ~> 1.9
   - **Verdict: reversed.** The branch already pinned `~> 1.9`, and that pin **breaks the host bundle**
     beside `redmine_view_issue_description` (finding C1). Now plain `gem 'deface'`, skipped when an
     earlier plugin declared it (`e4c4dc9`).

**Checks**

4. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible.
5. Check Redmine 7 webhooks against this plugin (see "Rules"), and note the result here even if nothing is needed.
6. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots).

   - 4: **done**, numbers under "Results". 5.1 not run locally and no longer required (Jan,
     2026-10-07); CI (5.1, 6.1, 7.0 × three databases) now runs only when started by hand.
   - 5: **done, nothing needed.** Core renders the issue payload with `issues/show.api.rsb` and empty
     params, so `include_in_api_response?('allowed_statuses')` is false and the only
     workflow-dependent part of an issue is never in a webhook. The plugin changes which status a
     user may pick, not issue data. Verified live: `issue_effect.mjs` receives a real
     `issue.updated` webhook for a status change made under a project workflow, with the new status
     and no `allowed_statuses`. Note: Redmine 7 refuses loopback webhook URLs
     (`WebhookEndpointValidator`), so the scenario listens on the container's own address.
   - 6: **done**, see "Function inventory".

## Migration session 2026-10-06: baseline (before any change)

Host: `jcatrysse/redmine` branch `7.0-stable-GEOxyz` @ `8067e23` (Redmine 7.0.1, Rails 8.1.3.1,
Ruby 3.3.6), built with `dev/setup.sh` into `.redmine/70geo-postgresql` (PostgreSQL 16.15) and
`.redmine/70geo-mysql` (MariaDB 10.11.14). Branch head `cdb32dd`.

| Check | PostgreSQL | MariaDB |
|---|---|---|
| Plugin migrations 001-007 up on a database built from core migrations | OK | OK |
| `VERSION=0`: no `workflows.project_id`, no plugin table, stock index set, 0 bookkeeping rows; then up again (7) | OK | OK |
| rspec (`dev/run.sh`) | **1350 examples, 0 failures** | **1350 examples, 0 failures** |
| `start_server.sh` (production) + `e2e.sh` smoke | 26 pages, 0 problems | (see e2e on MariaDB below) |
| `e2e.sh` core issue flows | 6 screenshots, 0 problems | |

Smoke notes: `/projects/e2e-project/workflow/{transitions,permissions,compare,graph}` and
`/projects/e2e-project/workflow_map` answer 404 in the smoke because it passes no `tracker_id`/`role_id`;
that is the plugin's documented refusal (`ExactSelection`), not a defect. The scenarios below open
them with a real selection.

Trap found while building the host: `dev/setup.sh` and `dev/sync.sh` resolve a **relative** target
directory after `cd`-ing into it, so `dev/setup.sh 7.0-stable postgresql 3.3.6 .redmine/x` copies the
plugin into `.redmine/x/.redmine/x/plugins/` and the host runs without it. Pass an absolute path.
Recorded, not fixed (outside the migration).

## Results (2026-10-06, final head)

| Check | PostgreSQL 16.15 | MariaDB 10.11.14 |
|---|---|---|
| rspec, this plugin alone | **1351 examples, 0 failures** | **1351 examples, 0 failures** |
| Migrations 001-007 up, `VERSION=0` (stock schema, 0 bookkeeping rows), up again | OK | OK |
| `dev/check-backfill.sh` (migration 004 backfill) | OK | OK |
| `dev/check-upgrade.sh` (four data shapes, downgrade, up) | OK | OK |
| `dev/check-uninstall.sh` (refusal, backup, all down, reinstall, restore, second restore) | OK | OK |
| `dev/check-release-upgrade.sh origin/main` (0.0.3 code, then this branch) | OK | OK |
| CI run 213 on `e4c4dc9` (the Gemfile fix): 5.1, 6.1, 7.0 x PostgreSQL, MySQL, MariaDB, lint, JS | green | |
| Boot + production eager load (`start_server.sh`, production) | OK | OK |
| e2e: smoke (26 pages) + core flows (6) + 9 plugin scenarios (`support.mjs` is a helper, also started by `e2e.sh`, does nothing) | **103 screenshots, 141 assertions, 0 problems** (after the review fixes) | **103 screenshots, 141 assertions, 0 problems** |
| RuboCop (`.github/lint`) | 162 files, no offenses | |

Screenshots: `docs/e2e/` (PostgreSQL, with one `<scenario>.md` table each) and `docs/e2e/mariadb/`.
Before pictures on 5.1 were not made: nothing in behaviour or layout changed in this session (the
only code change is the Gemfile).

**Together with other GEOxyz plugins** (`.redmine/70geo-together`, PostgreSQL, their
`redmine70-migration` branches where they exist): redmine_custom_workflows, redmine_issue_field_visibility,
redmine_depending_custom_fields, redmine_subtask, redmine_context_menu_actions (default branch),
redmine_tint_issues, redmine_parent_child_filters, redmine_view_issue_description,
redmine_extended_api, redmine_itil_priority, redmine_issue_todo_lists2, redmine_inline_edit_issues.

- Before C1 was fixed: `bundle install` refused the Gemfile, Redmine could not start.
- After: bundle, 369 migrations, boot OK; this plugin's rspec **1351 examples, 2 failures**: both
  are the core-drift gate (`compatibility_spec.rb:116`, `upstream/core_drift_spec.rb:103`) reporting
  that `WorkflowsController#permissions` under this plugin is redmine_itil_priority's, not core's.
  That is the gate doing its job, and it points at finding C2. On a verified Redmine (7.0 is) the
  plugin measures nothing at runtime, so users see no banner.
- e2e on that host (production, same scenarios): 11 runs, 103 screenshots, 140 assertions; 3
  problems, all from redmine_view_issue_description's own permission (`vid_authorize_issue_detail`
  answers 403 on `/issues/1` for the seeded Reporter and viewer roles, which lack
  `view_issue_description`). With that permission granted, `issue_effect` and `core` re-run with
  0 problems. Not an interaction with this plugin.
- C2 shown on that host: `WorkflowsController.ancestors` puts this plugin's patch in front of
  redmine_itil_priority's, and Administration → Workflow → Fields permissions has a Priority row but
  no Impact/Urgency rows: `docs/e2e/together/together-itil-core-permissions.png`.

Only the public GEOxyz plugins were combined; the private ones (agile, checklists, contacts,
helpdesk, people, tags, zenedit, ai_triage, resources, drive, questions, reporter) were not.
Among the public ones only redmine_view_issue_description declares `deface` in its Gemfile.

## Function inventory

Every function, how a user reaches it, the scenario that drives it (`test/e2e/`), and the
screenshots (`docs/e2e/<scenario>-<name>.png`; same names under `docs/e2e/mariadb/`). Users:
admin, manager (role "E2E full", every permission), viewer (only `view_project_workflow_rules`,
added by `test/e2e/seed.rb`), reporter (no plugin permission), outsider (no membership).

| Function | How a user reaches it | Scenario | Screenshots (what they prove) |
|---|---|---|---|
| Project settings → Workflow tab, one row per tracker x role | Project → Settings → Workflow (view or manage permission) | `project_settings_tab` | `manager-inherits`, `viewer-readonly` (no actions), `admin-private-tab`; refusals `reporter-no-settings`, `reporter-matrix-403`, `outsider-private-403` |
| Give own workflow (copy) / own empty / Empty / Return to generic (INV-3, three distinct states) | the tab, the matrix panel | `project_settings_tab`, `project_matrix` | `manager-own-copy`, `manager-own-empty`, `manager-perm-empty`; forged 404 for an unknown tracker, viewer's forged POST 403 |
| Project transitions matrix: read-only while inheriting, edit + Save when own | tab → count link | `project_matrix` | `inherits-readonly`, `own-saved` (generic untouched, INV-1), `viewer-own-readonly`, `invalid-tracker`, `invalid-status-refused` (forged status: nothing written, message shown) |
| Project field-permissions matrix | tab → Fields permissions | `project_matrix` | `permissions-inherits`, `permissions-saved`, `reporter-403` |
| Compare with the generic workflow | tab, matrix, inventory | `project_matrix` | `compare-permissions`, `compare-transitions`; bad `rule_type` 404 |
| Workflow diagram (SVG + table, unreachable/dead-end lists, ceiling, on/off setting) | tab, matrix, issue panel | `diagram` | `dense-folded`, `manager`, `over-ceiling`, `disabled-404` (and no link), `bad-tracker-404`, `viewer`, `reporter-403` |
| Effect on issues: status list follows the project workflow | issue edit form | `issue_effect` | `form-own-one-rule`, `viewer-generic` (another role unaffected), `status-changed` |
| "Workflow for this issue" panel (+ Deface links on the status field, both branches) | issue form, workflow icon next to Status | `issue_effect` | `panel-inherits`, `panel-own-empty` (no status field, the panel says why), `panel-own`, `outsider-panel-404` |
| REST `include=allowed_statuses` | API | `issue_effect` | agrees with the form in all three states (no screenshot: API) |
| Redmine 7 webhook on a status change | Administration → Webhooks | `issue_effect` | payload received by a local listener: `issue.updated`, new status, no `allowed_statuses` |
| Administration → Project workflows: menu entry, summary | Administration menu | `admin_rules` | `admin-menu`, `summary` |
| Admin transitions matrix over a selection (several projects, generic, "(No change)") | Project workflows → Status transitions | `admin_rules` | `matrix-two-inheriting`, `matrix-two-own`, `matrix-saved` (generic untouched) |
| Admin state actions over a selection, write ceiling | scope panel on the admin matrices | `admin_rules` | `matrix-two-empty`, `ceiling-refused` (nothing written) |
| Row/column Yes/No/(No change) actions with counter and Undo | every matrix | `admin_rules`, `core_workflow` | `bulk-row-no` (counter, Undo restores), `generic-column-no` (core screen: actions, no counter, finding M1) |
| Admin field-permissions matrix | Project workflows → Fields permissions | `admin_rules` | `permissions-two` |
| Bad selections refused (unknown, float-shaped, garbage ids) | URL / forged requests | `admin_rules`, `project_matrix` | `bad-selection-404`; forged PATCH 404 |
| Non-admins and anonymous on the admin area | URL | `admin_rules` | `manager-403` (also reporter, outsider, forged POST 403), `anonymous-login` |
| Copy screen (one workflow onto several projects) | Project workflows → Copy | `copy_workflows` | `copy-screen`, `copy-filled`, `copy-done`, `copy-no-target`, `manager-403` |
| Copy project carries "Project workflows (N)" (hook) | Project → Copy | `copy_workflows` | `project-copy-form`, `project-copy-result`; unticked: 0 copied |
| Workflow inventory | Project workflows → Workflow inventory | `admin_tools` | `inventory`, `inventory-all`, `inventory-bad-filter` |
| Diagnostics (ADR-002) | Project workflows → diagnostics link | `admin_tools` | `diagnostics` (7.0.1 tested, every patch present) |
| Plugin settings (thresholds, write ceiling, diagram) | Administration → Plugins → Configure | `admin_tools`, `diagram`, `admin_rules` | `settings`, `settings-invalid-fallback` (forged "abc" falls back to 50) |
| Copying a role or tracker copies its project rules | Administration → Roles / Trackers → Copy | `admin_tools` | `role-copied`, `tracker-copied` |
| Deleting a status that empties a project workflow warns | Administration → Issue statuses → Delete | `admin_tools` | `status-deleted-warning` |
| Core Administration → Workflow still edits the generic workflow only (INV-1, INV-4) | Administration → Workflow | `core_workflow` | `summary`, `generic-saved`, `generic-permissions`, `core-copy`, `manager-403` |
| Cross-link from core's workflow screen (Deface) | Administration → Workflow | `admin_rules` | asserted; visible in `docs/e2e/smoke-12.png` |
| Rake: backup (0600, FORCE), restore (OVERWRITE, junk file), deduplicate, uninstall refusal | shell | `rake_tasks` | `before-restore`, `after-restore`, `after-uninstall-refused`; full uninstall/reinstall: `dev/check-uninstall.sh` |
| Compatibility banner on an unverified Redmine | the seven write screens | not driven | 7.0 is verified, so no banner by design; covered by `spec/views/compatibility_banner_spec.rb` |
| Mail, cron, REST endpoints of its own, macros | none | n/a | the plugin has none |

## Findings of this session

- **C1 (fixed, `e4c4dc9`) Gemfile pin breaks the host bundle.** `gem 'deface', '~> 1.9'` plus
  redmine_view_issue_description's plain `gem 'deface'` makes Bundler refuse the Gemfile
  ("You cannot specify the same gem twice with different version requirements"), so Redmine does not
  start. Test in `plugin_conventions_spec.rb`, red on the old Gemfile.
- **C2 (fixed 2026-10-07, `a080401`, decision q3) redmine_itil_priority's Impact/Urgency on Fields permissions.**
  redmine_itil_priority prepends `WorkflowsController#permissions` (calls `super`, adds two rows)
  and extends `WorkflowPermission#validate_field_name`. This plugin prepends after it and replaces
  `#permissions` without `super` (deliberately: core's query has no `project_id` predicate, INV-4),
  and its `PermissionWriter` only accepts core fields and custom field ids. With both installed the
  two rows are not shown on Administration → Workflow → Fields permissions and could not be saved.
  0.0.3 on `main` replaces the action the same way, so this is not a regression of the migration.
  Proposed fix (not built, it touches INV-2/INV-4 code): scope `WorkflowPermission.rules_by_status_id`
  to `project_id: nil` in `WorkflowPermissionPatch` and drop the `#permissions` override so the
  action chain composes; let `PermissionWriter` accept a field name the model's own
  `validate_field_name` accepts. Built exactly so after Jan's decision q3.
- **M1 (open, pre-existing, nit)** README says the row/column actions come "with a count of what
  changed and an Undo" on every matrix; on core's own Administration → Workflow screen they work
  but have no counter or Undo (the undo region is rendered on the plugin's screens only). Same on
  5.1. `core_workflow.mjs` documents today's behaviour.
- **T1 (tooling, not fixed)** `dev/setup.sh` and `dev/sync.sh` resolve a relative target directory
  after `cd`-ing into it; pass an absolute path.

## Reviews

- **Own review, adversarial, in a fresh subagent** (diff `cdb32dd..HEAD`). No blocker, no invariant
  hit in production code. Accepted and fixed in the commit after `78a75ec`:
  the Gemfile comment quoted the new line where it meant the old one (a find-and-replace slip);
  docs and the spec overclaimed "either order" (a *later* pinned neighbour still fails; now said in
  the Gemfile, README, operations.md, DECISIONS and asserted as a refusal in the spec); the Gemfile
  now says the guard takes an earlier declaration as is; CHANGELOG and implementation-plan updated.
  E2E: the "abc falls back to 50" check was vacuous (now asserts the stored "abc" and threshold 50);
  the selection-size, Empty-both-projects, invalid-status flash, diagram dead-end/unused lists (the
  old caption wrongly called Rejected "unreachable"), diagram link positive control and
  core-summary cell (now one project rule fewer, exact cell compared) are now real checks; four
  `assert(true)` removed; `core_workflow` restores the generic rows it touched from a snapshot in
  `finally` (it used to copy Manager's rules over Developer's); `reset()` re-seeds the E2E roles'
  generic workflows and switches webhooks off; fixture writes that bypass the writers are commented;
  captions corrected. Not changed: Bundler's "listed more than once" warning (now silenced in the
  spec), a deface version check in `init.rb` (left as open question 2).
- **OpenAI review** (`./.codex/openai_review.sh`, gpt-5, `4e3f6d2..e713b5b`, 19 files):
  **no findings**. `docs/reviews/openai-2026-10-06-e713b5b.md`.
- **OpenAI review, second run** (`4e3f6d2..30b313b`, after the fixes above): two findings, both
  accepted and fixed with a test, see `docs/reviews/openai-2026-10-06-30b313b.md`: the Gemfile guard
  stepped aside for an earlier deface confined to a non-default group or platform (production would
  then miss deface); the webhook step threw on a host without a non-loopback IPv4 (now SKIP).
- **OpenAI review, third run** (`4e3f6d2..60a5e4b`): **no findings**,
  `docs/reviews/openai-2026-10-06-60a5e4b.md`.
- After the last fix only `issue_effect.mjs` was re-run in the browser (MariaDB, 0 problems); the
  full set on both databases ran on `30b313b`, whose only later changes are the Gemfile guard
  (covered by rspec on both databases and the combined host's bundle) and that scenario.

## Decided by Jan (2026-10-07)

Answered by Jan on 2026-10-07 in the coordinating session (recorded verbatim in
`docs/DECISIONS-2026-10-07.md`); final.

**General, for every GEOxyz plugin**
- GEOxyz goes straight to Redmine 7: no backports to 5.1; `redmine70-migration` is what goes live.
  Redmine 5.1 compatibility is no longer a requirement (rule below updated).
- Production is PostgreSQL 16 only; tests and e2e run on PostgreSQL. A MariaDB-only problem is a
  note, not a blocker (rules and definition of done below updated). The MariaDB results of
  2026-10-06 stay above as a record.
- deface is required without a version constraint (see q2).
- A core method other plugins also patch is patched with `prepend`, never `alias_method`.
  **Checked:** this plugin has no `alias_method` at all (`grep -rn alias_method lib app init.rb`:
  comments only); every patch is a `prepend`, a singleton `prepend` or `helper`. With the 12 other
  GEOxyz plugins installed, Project → Settings, the issue list and an issue page answer 200 (smoke
  on the combined host, see Results). `RMP_EXTRA_PLUGINS` is not supported by this repo's `.codex`
  copy, so the combined host is `.redmine/70geo-together`, built by `dev/setup.sh`.
- GitHub Actions stay manual only (see q1).

**Decisions for this plugin**
1. **q1 CI triggers.** Jan chose B: "Alleen handmatig, zoals de andere GEOxyz-plugins" (Volgt de
   afspraak, maar fouten vallen pas op als iemand de testen zelf start.).
   **Done in `d4e2b3e`:** `specs.yml` runs on `workflow_dispatch` only; CLAUDE.md, README,
   operations.md and dev/README updated; conventions spec red before, green after.
2. **q2 deface without a version limit as a rule for all plugins.** Jan chose B: "Aanvaarden plus
   afspraak voor alle GEOxyz-plugins" (Elke GEOxyz-plugin vraagt deface voortaan zonder versie of
   met dezelfde beveiliging, telkens wanneer zijn Gemfile toch aangepast wordt.).
   **No code needed here** (this plugin already does it, `e4c4dc9`/`60a5e4b`, with tests). The
   general rule, written down for every GEOxyz plugin:

   > A GEOxyz plugin that depends on deface declares it in its Gemfile **without a version
   > requirement**, either plainly (`gem 'deface'`) or with this plugin's guard:
   > `gem 'deface' unless dependencies.any? { |d| d.name == 'deface' && d.groups.include?(:default) && d.platforms.empty? }`.
   > Reason: Redmine evaluates every plugin Gemfile into one Bundler DSL and Bundler refuses the
   > same gem declared twice with different requirements, so one plugin's version limit stops
   > `bundle install` for the whole installation. Apply it whenever a plugin's Gemfile is touched.

3. **q3 Impact and Urgency on Fields permissions.** Jan chose A: "Apart herstellen, met eigen
   tests" (Een aparte wijziging laat beide plugins samen werken op dat scherm, maar raakt gevoelige
   code van deze plugin.).
   **Done in `a080401`, fixed in this plugin** (the cause was here, not in redmine_itil_priority):
   core's `WorkflowsController#permissions` is no longer replaced; its unscoped query
   `WorkflowPermission.rules_by_status_id` is scoped to the generic workflow instead (INV-4 holds),
   and `PermissionWriter` accepts a field name the model's own `validate_field_name` accepts (INV-2
   holds: digits must still name a custom field, unknown names are dropped).
   Follow-up **`b112e7a`**: the drift gate took ITIL's prepended wrapper for core's body; it now
   skips modules other plugins prepend, so the plugin's suite is green with the GEOxyz plugins too.
   Not covered (left as is): the plugin's *own* matrices (project and administration Fields
   permissions) list core fields and custom fields only, so per-project Impact/Urgency rules are
   not offered there.

### Review of the decision commits (2026-10-07)

Own adversarial review in a fresh subagent, over `638eb88..29cde11`:
- **Blocker, fixed:** the writer's new field-name probe let a name through that core's
  line-anchored `/^\d+$/` accepts (`"\n5"`, `"5\n<svg…>"`), so an arbitrary string could reach
  `workflows.field_name` (INV-2). Now only a plain identifier (`/\A[a-z_][a-z0-9_]*\z/`) is put to
  the model; a spec with those names was red before the fix.
- **Major, recorded for Jan (open question below):** after a takeover, a project holds a copy of the
  generic Impact/Urgency rules, and they are enforced, but the plugin's own project matrices do
  not offer those fields. Behaviour is unchanged by the takeover; editing them per project is not
  possible. Pinned by a spec.
- Minor, fixed: design.md and a patch comment still described `#permissions` as replaced; the
  render spec now really renders (with a note that it is coverage, not the regression test); e2e
  forged request checks the HTTP status and the rule lookup is filtered; stale CI claims reworded.
- Not built (suggestion): Diagnostics could list other plugins' modules in front of a shadowed
  method; the drift gate no longer reports them since `b112e7a`.

## Open questions for Jan

1. **Impact/Urgency per project.** A) offer a neighbour's fields on the plugin's project and
   administration Fields permissions matrices too (reads the generic rows' field names the model
   accepts; more code in the matrix helpers); B) leave it: projects carry the generic rule along on
   takeover and can change it only by emptying the workflow or returning to the generic one.
   Recommendation: B until GEOxyz needs a project-specific Impact/Urgency rule; then A.

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- claude/dev migrations 004-006 rename permissions: after the upgrade check the roles' permissions (Administration > Roles) and the project-specific workflows.
- From `main` (0.0.3) the migrations are 004-**007**: 004 backfills one "own workflow" decision per
  project/tracker/role that has rules, 005 drops two redundant indexes, 006 renames
  `view_project_workflow`/`manage_project_workflow` to `..._rules` (grants carried across), 007 adds
  the write-lock table. Run `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
  Rehearsed with real 0.0.3 code on Redmine 7 (PostgreSQL and MariaDB): behaviour unchanged, rules
  untouched.
- Take a backup of the project workflows first, with the **old** release still installed if
  possible, and in any case right after the upgrade:
  `bundle exec rake redmine_project_workflows:backup FILE=/path/backup.json RAILS_ENV=production`.
- `bundle install` is needed (Gemfile changed: plain `gem 'deface'`). With
  `redmine_view_issue_description` installed, the previous `~> 1.9` pin would stop the bundle.
- Optional, once: `rake redmine_project_workflows:deduplicate_workflow_rules RAILS_ENV=production`
  removes exact duplicate rows older installations can carry (it deletes nothing else).
- If `redmine_itil_priority` is installed: Impact/Urgency rows on Administration > Workflow >
  Fields permissions are shown and saved again (finding C2, fixed, decision q3); with 0.0.3 they
  were not. Check that screen once after the upgrade. Per-project Impact/Urgency rules are not
  offered on the plugin's own project matrices.
- GitHub Actions of this plugin no longer run on push; start `Specs` by hand from the Actions tab
  before a release (decision q1).
- Nothing to do for mail, cron, files or settings: the plugin sends no mail, has no cron job, and
  its settings keep their defaults.

## How to test

This plugin has its own developer scripts in `dev/` (see dev/README.md): use `dev/setup.sh` and `dev/run.sh`. They put rspec-rails and rails-controller-testing in the host's Gemfile.local on purpose; keep it that way.

For the real Redmine and the browser checks, point the shared scripts at the Redmine checkout `dev/setup.sh` made (`REDMINE_DIR=<that checkout>`; it needs a `test` entry in its config/database.yml):

```sh
./.codex/start_server.sh       # real Redmine (production mode) with this plugin, seeded users and projects
./.codex/e2e.sh                # browser: smoke over the plugin's pages, core issue flows, test/e2e/*.mjs
./.codex/openai_review.sh      # independent OpenAI review of the diff, only when OPENAI_API_KEY is set
```
Write one scenario per function in `test/e2e/<function>.mjs` (example at the top of
`.codex/e2e/lib.mjs`); screenshots and a table per scenario land in `docs/e2e/`. Users:
`admin`, `manager` (every permission), `reporter` (no plugin permissions), `outsider` (no
membership); password `Redmine7Test!`. Needs Node with Playwright and Chromium
(`npm install -g playwright && npx playwright install --with-deps chromium`).

The coordinator's harness (`plugin-check.sh` in the migration kit, kept outside this repo) adds a
browser smoke test of every page the plugin adds and runs all GEOxyz plugins together; the
results quoted in the analysis come from it.

## How the migration session works (same for every plugin)

1. **Start**: `git fetch && git checkout redmine70-migration && git pull`. Read this whole file,
   including the analysis report at the bottom. Do not reopen decisions recorded here.
2. **Baseline, before you change anything**:
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL and with MariaDB;
   - a real running Redmine with this plugin (`./.codex/start_server.sh`) and the browser run
     (`./.codex/e2e.sh`: smoke over every page the plugin adds, plus the core issue flows).
   Write the numbers here. Something already broken now is a finding, not your regression.
3. **Inventory of functions**: list every function of the plugin in this file, in a table
   "function | how a user reaches it | scenario | screenshot". Take them from the README,
   `init.rb` (permissions, menus, settings, project modules), routes, hooks and view
   overrides, macros, mail handling, API endpoints, rake tasks and cron jobs. This table is the
   coverage list for step 8; a function that is not in it will not be tested.
4. **GEOxyz changes**: go through the table above, one item at a time. Each kept or re-made change
   is its own commit with a test that proves it. Record the verdict in the table.
5. **Work list**: then the numbered list, in order. One concern per commit.
6. **Portability**: everything must run on Redmine's supported databases (PostgreSQL,
   MySQL/MariaDB; SQLite where the plugin already supports it). Migrations must be reversible and
   are run down and up on PostgreSQL and MariaDB.
7. **Together**: run with the other GEOxyz plugins installed (the migration kit's harness, or
   `RMP_EXTRA_PLUGINS`). A failure that only appears in combination is a finding to record here.
8. **End to end, visually, every function**: on the real Redmine from `start_server.sh`
   (production mode, the way GEOxyz runs it), write one scenario per function in
   `test/e2e/<function>.mjs` with `.codex/e2e/lib.mjs` and run them with `./.codex/e2e.sh`.
   - Each function as the users that matter: `admin`, `manager` (every permission, the
     plugin's included), `reporter` (member without the plugin's permissions), `outsider`
     (no membership, private project must stay invisible).
   - The failure paths too: setting off, permission absent, empty state, invalid input, the
     value that used to raise. A refusal that is shown is evidence as much as a success.
   - One screenshot per function and per path, with a caption saying what it proves. Open
     every screenshot and look at it: a picture nobody looked at proves nothing. Commit them
     in `docs/e2e/` and list them in the inventory table.
   - Functions without a page (mail in and out, REST API, rake tasks, cron, webhooks): exercise
     them against the same running instance (mails land in `redmine/tmp/mails`, `t.mails()`
     reads them; API through `t.page.request`) and record command and result.
   - Before pictures where behaviour or layout changes: the branch GEOxyz runs today, on
     Redmine 5.1, same scenarios, `RMP_E2E_OUT=docs/e2e/before`.
   - Run the whole e2e set once on MariaDB as well (`RMP_DB=mariadb`, then `start_server.sh --reset`).
9. **Independent review**: first your own, adversarial: re-read the whole diff as if someone
   else wrote it and you are paid to reject it. Then, **when `OPENAI_API_KEY` is set in the
   session**, `./.codex/openai_review.sh`: it sends the diff of this branch to an OpenAI model
   and writes `docs/reviews/openai-<date>-<sha>.md`. Every finding gets a `Resolution:` line
   there (fixed in <commit>, with a test, or why not). Fix, re-run the tests and the e2e set,
   and run the review again until it has nothing new that you accept. Without the key: write
   "OpenAI review: skipped, no OPENAI_API_KEY" in the report; never send code anywhere else.
10. **After the upgrade**: anything the production upgrade must do for this plugin (data fixes,
    settings, cron, files, removed features) goes into the section "After the upgrade".
11. **Finish**: update "Status", the inventory and the work list in this file, push
    `redmine70-migration`, and report: what changed, test numbers on both databases, e2e
    numbers (scenarios, screenshots, problems), the review result, what is left, what needs Jan.

### Stop and ask Jan when
- a GEOxyz change would be lost or behave differently for users;
- a new gem, a new setting with user impact, or a schema change not required by Redmine 7 seems needed;
- the change would send data to an external service (the OpenAI review of the code diff is the
  one exception Jan approved, and only when the key is present);
- upstream and GEOxyz disagree on behaviour and both are defensible.

## Rules

- **Target**: Redmine 7.0-stable-GEOxyz (https://github.com/jcatrysse/redmine), Rails 8.1, Ruby 3.3+.
  Core sources for comparison: branches `5.1-stable`, `6.1-stable`, `7.0-stable`, `7.0-stable-GEOxyz`.
- **Evidence**: never report a test, lint, browser check or review as passed without having seen
  it. Quote the summary lines; list the screenshots. "Should work" is not a result, and a green
  test suite is not proof that a feature works in the browser.
- **Tests**: never skip, delete or weaken a test. A test that encodes Redmine 5 markup or
  behaviour is updated to Redmine 7, with the reason in the commit. Every fix gets a test that
  fails without it.
- **Minimal diffs** in the plugin's own style. No reformatting, no unrelated refactoring.
  Something wrong elsewhere: write it down here, do not fix it in passing.
- **Security**: authorization on every action and entry point; `safe_attributes`, never
  `to_unsafe_hash` into `update`; no SQL built from params; no secrets in logs; no `html_safe` on
  user input.
- **Webhooks (new in Redmine 7)**: core sends issue payloads (core `issues/show.api.rsb`, rendered
  as the webhook owner) to webhook endpoints, past plugin hooks and controller patches. If the
  plugin hides, adds or changes issue data, make webhooks consistent with that or record why not.
- **Redmine 7 conventions**: SVG icons through `sprite_icon` (the `icon icon-*` CSS is gone),
  Propshaft assets under `assets/` (`/assets/plugin_assets/<id>/...`), the new header and user menu,
  `ContextMenus::*Controller`, Loofah-based text formatting, Chart.js as an ES module, sudo mode
  (on by default: `t.sudo()` in a scenario). The breaker list is in the migration kit's CHECKLIST.md.
- **Locales**: keep the locales the plugin ships in sync; translate a new key by matching the
  closest existing key in the same file, not from scratch; do not add new languages.
- **Redmine 5.1**: not a requirement any more (Jan, 2026-10-07): GEOxyz goes straight to Redmine 7
  and nothing is backported. Do not add code paths that exist only for 5.1.
- **Databases**: production is PostgreSQL 16; tests and e2e run on PostgreSQL. Keep SQL portable
  where that costs nothing; a MariaDB-only problem is a note here, not a blocker (Jan, 2026-10-07).
- **deface**: declared without a version requirement (rule under "Decided by Jan", q2).
- **Patching core**: a core method other plugins also patch is patched with `prepend`, never
  `alias_method` (Jan, 2026-10-07).
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL, alone and with the
  other GEOxyz plugins (numbers in this file; MariaDB no longer required since 2026-10-07); boot, production-like eager load, migrations up/down OK.
- Every function in the inventory exercised end to end on a real running Redmine, with and
  without permissions and on its failure paths; `./.codex/e2e.sh` green; screenshots looked at,
  committed in `docs/e2e/` and listed.
- Review done: your own, and the OpenAI review when the key is present, every finding resolved
  in `docs/reviews/`.
- No new failure when run together with the other GEOxyz plugins.
- "After the upgrade" lists every action production needs; "Status" is current.


## Analysis report (2026-10-06, Dutch)

# redmine_project_workflows
- Gebruikte branch: main @ d61b1de (2026-08-28) - plugin id redmine_project_workflows, versie 0.0.3
- Upstream: geen (eigen plugin, jcatrysse/redmine_project_workflows is geen fork)
- Fork t.o.v. upstream: n.v.t.
- Andere relevante branches: `origin/claude/dev` @ 8a10819 (2026-08-29) is **210 commits voor en 4 achter** main (de brief zegt omgekeerd "4 ahead / 210 behind"; gemeten met `git rev-list --count`). De 4 commits die alleen op main staan zijn review-/findings-docs. claude/dev is een grote herschrijving (versie 0.1.6, +15.9k regels: eigen admin-schermen i.p.v. 11 Deface-overrides, workflow-diagram, backup/restore, rake-tasks, migraties 004-006 incl. hernoemen van permissies, CI-matrix 5.1/6.1/7.0). Niet gemerged (feature-werk, claude/* niet aanraken), wel informatief getest: harness `origin/claude/dev` (results/1006-094046-s5-redmine_project_workflows_origin_claude_dev): OK bundle, boot (0.1.6), eager load, migraties 001-006 dev+test, rollback 0 en terug, smoke 72/72 zonder 500 (12 plugin routes, `/projects/geoxyz-verify/workflow/*` geven 404 omdat de smoke geen `tracker_id`/`role_id` meegeeft: `find_tracker_and_role` -> `render_404`, by design); rspec niet uitvoerbaar omdat claude/dev rspec-rails bewust uit de plugin-Gemfile haalde (harness meldt dat als FAIL "no summary"); het lost wel exact het hieronder gevonden toggle-probleem op (`project_workflows_toggle_multiselect_tag`). `origin/claude/redmine-workflows-review-zpugog`: 1 commit (test harness), oud.
- Baseline: Gemfile `deface` (ongepind) + test: rspec-rails, rails-controller-testing; 3 migraties (kolom `workflows.project_id`, indexen, FK met cascade); rspec (11 spec-bestanden, 63 examples); 5 Deface-overrides op `workflows/edit`, `workflows/permissions`, `workflows/copy`; prepends op Issue, Project, WorkflowsController, WorkflowsHelper, WorkflowTransition/WorkflowPermission/WorkflowRule (class methods).

## 1. Werkt out of the box op Redmine 7?   DEELS
Harness `redmine_project_workflows@origin/main` (results/1006-085329-s5-redmine_project_workflows_origin_main):
- OK bundle (deface 1.9.0 op Rails 8.1.3.1), boot, eager load, migraties dev+test
- OK rspec 63 examples, 0 failures (met rspec in PATH, zie harness-opmerking)
- WARN js-error `/workflows/edit` en `/workflows/permissions`: "Cannot read properties of undefined (reading 'getElementsByTagName')" - `app/views/redmine_project_workflows/_project_selector.html.erb:7` rendert `<span class="toggle-multiselect icon-only"></span>` zonder de `sprite_icon('')` die core sinds 6.0 in die span zet; `toggleMultiSelectIconInit()` (application-legacy.js:1186) roept `updateSVGIcon(undefined)` aan. Gevolg: JS-fout bij elke pageload van die twee schermen en de project-multiselect-knop is onzichtbaar (lege icon-only span).
- OK smoke 60/60.

Deface-selectors tegen 7.0-markup (gemeten door de pagina's als admin te renderen): alle 5 overrides grijpen nog - project-select `project_id[]` op edit en permissions (insert_before `submit_tag l(:button_edit)`), hidden `project_id[]` in `div.autoscroll` (insert_top), `source_project_id` + `target_project_ids[]` op copy (insert_after `select_tag('source_role_id'` / `select_tag 'target_role_ids'`). De ankers zijn in 7.0 ongewijzigd t.o.v. 5.1 (copy.html.erb identiek; edit/permissions alleen sprite_icon-wijzigingen).

## 2. Upstream sync?   GEEN UPSTREAM

## 3. Werkt na sync op Redmine 7?   n.v.t.

## 4. Complexiteit en blokkers   score 1
- Blokkers: `app/views/redmine_project_workflows/_project_selector.html.erb:7` - lege toggle-span -> JS-fout op workflow edit/permissions - `sprite_icon('')` renderen als `Redmine::VERSION::MAJOR >= 6` (versiecheck i.p.v. `respond_to?(:sprite_icon)`, omdat redmineup/redmine_ai_triage op 5.1 een sprite_icon back-porten; zelfde redenering als claude/dev) (gefixt in d98de23). Na fix: alle toggle-spans bevatten een svg, geen JS-warnings meer in de smoke.
- Monkey patches t.o.v. 7.0 (gediffed 5.1 vs 7.0):
  - `WorkflowTransition.replace_transitions` - in 7.0 herschreven voor performance (#43957: group_by-lookup i.p.v. `records.select` per cel). De plugin vervangt de methode **volledig** (geen `super`) door `TransitionWriter.replace_transitions_for_project_id(nil, ...)`, dat al bulk werkt (gerichte `delete_all` + `insert_all` in slices van 1000). De core-optimalisatie wordt dus niet gebruikt maar is ook niet nodig; geen conflict. Idem `WorkflowPermission.replace_permissions` (core ongewijzigd).
  - `WorkflowsController#update/#update_permissions/#permissions` (7.0: alleen `each_value`/`delete_suffix`-refactor; plugin roept `super` buiten projectcontext, en kopieert de permissions-logica met identieke output), `find_trackers_roles_and_statuses_for_edit`, `find_statuses`, `copy`, `duplicate` - alle bestaan nog met dezelfde before_action-structuur.
  - `Issue#workflow_rule_by_attribute`, `Issue#new_statuses_allowed_to`, `Issue#roles_for_workflow`, `Project#rolled_up_statuses`: byte-identiek in 5.1 en 7.0.
  - `WorkflowsHelper` (options_for_workflow_select, field_permission_tag, transition_tag): core-helper ongewijzigd; `_form.html.erb` gebruikt in 7.0 `toggle_checkboxes_link`, raakt de plugin niet.
  - `WorkflowRule < ApplicationRecord` in 7.0: `insert_all`/`delete_all` op WorkflowTransition werken (rspec groen).
- Stille breuken:
  - `init.rb:19` patches + Deface-overrides worden toegepast in `config.after_initialize` vanuit init.rb (dat zelf in `to_prepare` draait): eerste boot OK, maar na een code-reload in development worden de prepends niet opnieuw gezet. Productie (cache_classes) niet geraakt; was op 5.1 identiek.
  - `lib/redmine_project_workflows.rb:3-15` `require_relative` van bestanden onder de plugin-`lib` (een Zeitwerk-autoload-pad in Redmine 6+/7): eager load slaagt wel (gemeten), dus geen blokker.
  - Gemfile: `deface` ongepind; 1.9.0 werkt op Rails 8.1. Een toekomstige deface 2.x kan de override-API wijzigen (claude/dev pint `~> 1.9`).
  - Migratie 001 `down` verwijdert alle projectspecifieke regels (rollback getest: OK).
- Overlap met Redmine 7 core: geen (core kent nog altijd geen per-project-workflows; #43957 is alleen performance).
- Open werk voor ansif:
  1. Beslissen of claude/dev (0.1.6, eigen schermen, eigen CI op 7.0) main vervangt; dan vervalt de Deface-afhankelijkheid grotendeels. Zo niet: deze ene fix op main volstaat voor R7.
  2. Optioneel `deface` pinnen op `~> 1.9` in Gemfile.

## Branch redmine70-migration
- Basis: origin/main @ d61b1de
- Commits: d98de23 Render the multiselect toggle icon on Redmine 6+
- Eindresultaat harness (herhaald met de bijgewerkte harness van 09:25, results/1006-092816-s5-redmine_project_workflows_redmine70-migration): OK bundle, boot, eager load, migraties dev+test, rollback 0 en terug; OK rspec 63 examples, 0 failures; OK smoke 60/60, geen JS-warnings. (Ook de eerdere runs draaiden rspec echt: ik zette `/opt/rbenv/versions/3.3.6/bin` in PATH.)
- Rollback migraties: OK


## Aanvulling coordinator (2026-10-06, tweede ronde)
Op vraag van Jan gaat GEOxyz van main naar de nieuwe lijn. `redmine70-migration` bevat nu een merge van `origin/claude/dev` (0.1.6) in de vorige migratiebranch (4633811). De partial die d98de23 repareerde bestaat in claude/dev niet meer; die fix vervalt, claude/dev rendert de toggle zelf.
Gemeten met de harness (test-gems rspec-rails en rails-controller-testing via Gemfile.local, zoals dev/setup.sh doet):
- PostgreSQL: boot, eager load, migraties 001-006, rollback naar 0 en terug OK, **rspec 1350 examples, 0 failures**, smoke 72/72.
- MariaDB 10.11: identiek, **1350 examples, 0 failures**, rollback OK, smoke 72/72.

