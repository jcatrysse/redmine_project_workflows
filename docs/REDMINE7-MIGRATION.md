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
| Runs on Redmine 7 as is | DEELS |
| Upstream sync | GEEN UPSTREAM |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 1 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz + latest 7.0-stable), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16 and MariaDB 10.11 |
| Branch head when this file was written | `4e3f6d2` |

## Already on this branch

- `d98de23` Render the multiselect toggle icon on Redmine 6+
- `4633811` Merge claude/dev (0.1.6) into redmine70-migration

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Open items from the analysis** (Dutch; where they repeat a priority item, the priority item wins)

1. Decide whether claude/dev (0.1.6 rewrite, 210 commits ahead of main, own CI incl. 7.0) replaces main
2. claude/dev boots, migrates (001-006, rollback OK) and smokes 72/72 on R7; its rspec could not run in the harness (rspec-rails removed from plugin Gemfile)
3. Optionally pin deface ~> 1.9

**Checks**

4. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible.
5. Check Redmine 7 webhooks against this plugin (see "Rules"), and note the result here even if nothing is needed.
6. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots).

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- claude/dev migrations 004-006 rename permissions: after the upgrade check the roles' permissions (Administration > Roles) and the project-specific workflows.

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
- **5.1 compatibility**: prefer fixes that also run on Redmine 5.1 so they can be merged early;
  say so when a fix cannot.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why).
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL and MariaDB
  (numbers in this file); boot, production-like eager load, migrations up/down OK.
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

