# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP8** are **done**, and have been since the
  session before this one. `docs/implementation-plan.md` runs WP0..WP8 and every
  row of its table reads *done*. There is no WP9. What happens now is the
  **review loop** in `docs/review/`: an outside reviewer files findings, a
  fixing session acts on them. This session was a fixing session.
- **What exists:** the plugin at **0.1.0** — the scope model (WP1), the core
  seams (WP2), the per-scope summary page and inventory (WP3), the Workflow tab
  in project settings behind two permissions (WP4), row and column actions on
  every transition matrix (WP5), an audit trail, a project-versus-generic
  comparison screen and a counter with undo (WP6), the documentation, locale and
  release pass (WP7), and the workflow panel on the issue form (WP8).
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. It overrides whatever name the
  environment gives a session — this one started on
  `claude/codex-plugin-review-2026-3r2wgk`, which **did not exist on the remote
  and was never pushed**, and checked out `claude/dev` before touching anything.
  **Pull before you start**, and note that the *local* ref can be stale even when
  the remote is current: `git checkout -B claude/dev origin/claude/dev` is the
  safe form.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** **one**, new this session, and it blocks nothing — what the
  copy screen should do when no target project is selected (finding C01, below).
  It is written out with options and a recommendation under "Open — for Jan" in
  `docs/DECISIONS.md`.
- **Open findings:** **three**, all deliberate. `G02` and `G03` from the earlier
  runs (both recorded with the reasoning for leaving them), and `C01` from this
  session, which is waiting on Jan rather than on code. Everything else across
  every findings file is closed. To check for yourself:
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/`.
- **`spec/characterization/`:** still **gone**, since WP3. The convention stands
  and is written down in `dev/README.md`: a defect that is found but not yet
  fixed is pinned there first.

## What this session produced

A fixing session against **`docs/review/findings/2026-08-26-codex.md`** — a
review run by ChatGPT Codex on `db381fc`, read-only, no suite run. Two findings,
one major and one minor. Both are now **fixed**, in one commit, `7ff8293`.

### The defect, which was one defect and not two

Redmine's `WorkflowsController#find_sources_and_targets` — byte-identical on
5.1, 6.1 and 7.0 — resolves the copy screen's four "which workflow" selectors
loosely, and neither loss is reported:

- A **source** tracker or role id that names nothing resolves to `nil`. So does
  the deliberate `any` selection, which `WorkflowRule.copy` reads as "use the
  target's own". The two are then indistinguishable: `source_tracker_id=999999`
  with a real role copies *that role's rules from every tracker*, and reports
  success.
- A **target** tracker or role id that names nothing is simply dropped by
  `where(id: values)`. One live tracker plus one deleted one is applied to the
  live one, and reported as success for both.

Every write on that screen deletes the target pair's existing rules before
inserting, so in both cases what ran was a *destructive* copy that nobody asked
for. The plugin makes this worse than core does, because it can apply one
request to several projects at once — which is why Codex filed it here.

### The fix

`WorkflowsControllerPatch#duplicate` now calls **`invalid_copy_selection?`**
before anything is written:

- A source selector supplied as anything other than `any` must be an all-digit
  id that resolved to a record. The **shape** is checked as well as the record,
  because core resolves with `to_i`, so `'12abc'` silently meant tracker 12.
- Every submitted **target** id must appear among the records core resolved,
  de-duplicated first — the exact-set rule the target *projects* have been held
  to since WP0, now covering all four selectors. It costs no query: the
  comparison uses the records `find_sources_and_targets` had already loaded.

**The part that was wider than the findings said.** Both findings place the
defect in the plugin's project branch. But `#duplicate` hands a request that
carries no project parameter to core, and the copy form's target project
selector is a `multiple` select — one with nothing selected submits **nothing at
all**. So the unguarded path was reachable from the plugin's own form, not only
from a hand-built request. The guard therefore runs on **every** request, before
the delegation to core.

**Messages.** An unresolvable source tracker or role reports core's own
`error_workflow_copy_source` ("Please select a source tracker or role"), which
names what is actually wrong and is already translated in every language Redmine
ships. A target tracker or role that does not exist gets a new plugin key,
`error_workflow_copy_target_tracker_or_role`, added and translated in all eight
locale files — parallel to `error_workflow_copy_target_project`, and deliberately
not merged with it, because "you selected nothing" and "what you selected is
gone" send an administrator to look at different things.

### The finding this session raised and did **not** fix

**C01**, in `docs/review/findings/2026-08-26-copy-form-observations.md`. Found
while widening the guard, confirmed, major, and left open on purpose:
`CLAUDE.md` says an out-of-scope defect goes into a findings file, not into the
diff.

Selecting **no target project at all** on the copy screen sends the request to
core, which rewrites the **generic** workflow — the one every project that has
not overridden it inherits — and reports "Successful update". The plugin's own
error text already promises a target project is required
("Please select target trackers, roles, **and projects**"); that check is simply
never reached on this path, because a `multiple` select with nothing selected
submits no parameter. Nothing regressed — this is Redmine's behaviour and the
plugin inherited it — but the plugin's form is what makes the slip easy.

Three options, written out in `docs/DECISIONS.md` under "Open — for Jan":
refuse the request (safest, but a bare core-shaped copy request stops working);
preselect *Generic* in the target selector (nothing that works today breaks, and
the destructive default becomes visible); or leave it. The recommendation is the
second, then the first once Jan is sure nothing in his installation posts a bare
copy request.

### The review roles, and one that could not run

Implementer, independent reviewer, QA and UX all ran. The **independent review
was done in this same context, not in a fresh subagent** — `CLAUDE.md` asks for a
fresh one "if a subagent mechanism is available", and this session was started
with subagents explicitly disallowed. Read the review pass accordingly: it is
self-review, which defends its own reasoning, and it is the weakest of the four
gates this session. What it did produce, each of which became an example:

- The symmetric malformed id (a source **role** shaped like `'2abc'`), because a
  guard tested on one of two selectors is how one of two places gets missed.
- The **no-project-named** path, for a bad source *and* for a bad target.
- A **blank** source tracker, asserting the new guard does **not** intercept it
  and the pre-existing message is still the one shown.
- The snapshot the examples compare is both tables — `workflows` **and**
  `project_workflow_scopes` — so a rejected request that recorded a scope for a
  copy that never happened (INV-3) would be caught too.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | **580 examples, 0 failures** (was 566; 14 added) |
| Plugin suite, 6.1-stable + PostgreSQL 16 | **580 examples, 0 failures**, and again with `--seed 777` |
| Plugin suite, 7.0-stable + PostgreSQL 16 | **580 examples, 0 failures**, and again with `--seed 4242` |
| Fails on the old code | **10 of the 14 new examples**, run rather than assumed: `git stash push lib/…/workflows_controller_patch.rb`, suite, `git stash pop`. Each of the ten had written a workflow row and redirected with the success notice instead of rejecting. The other four are the positive controls that must pass both before and after — `any` as a source tracker, `any` as a source role, the same target tracker id submitted twice, and a blank source tracker still reporting the older message |
| RuboCop | 91 files, no offences, **no new `.rubocop_todo.yml` entry** |
| `zeitwerk:check` | passes on the 7.0 host |
| Migration up → 0 → up | clean on the 7.0 host, run **before** its suite. This session adds no migration |
| Locale parity | eight files, **92** keys each (was 91) |
| MySQL / MariaDB | **not run** — no such server and no `mysqld` in this container. Three of the nine cells are unverified locally; CI covers them |
| CI | **not yet observed for `7ff8293`.** The push landed; the next session should read the run for that commit before anything else |

## Exact next step

**Read CI for `7ff8293`, then it is Jan's turn again.**

1. **Check CI on the head.** `7ff8293` is pushed to `claude/dev` and its run had
   not finished when this session ended. Nine cells plus RuboCop; the three
   **MySQL and MariaDB** cells are the ones nothing in this container can run, and
   the change touches parameter parsing rather than SQL, so they are unlikely to
   differ — but "unlikely" is not "checked". If a cell is red, fix it before
   anything else. (Beware: a run can read "cancelled" because the concurrency
   group superseded it when a later commit was pushed. Read the *head's* run, not
   the newest completed one.)
2. **Nothing else is queued.** WP0..WP8 are done, `spec/characterization/` is
   empty, and the three open findings are all deliberate — `C01` is waiting on
   Jan, `G02` and `G03` were both recorded with the reasoning for leaving them.
   The branch is waiting for Jan to review it and ask for the merge.
3. **If Jan answers C01,** the fix is small and lives in one place:
   `#duplicate`'s delegation to core (`return super unless project_context?`) for
   option A, or
   `app/views/redmine_project_workflows/_copy_project_selector.html.erb` for
   option B. Either needs a controller example and, for B, a view example — and
   B changes what an administrator sees, so it needs a line in the CHANGELOG.
4. If Jan wants more than that, the candidates already written down are: the
   **layered SVG diagram** (option A in `docs/DECISIONS.md`, which is WP8's data
   with a layout pass added); the **issue show page**, deliberately out of WP8's
   scope; **row and column actions on the field-permissions matrix** (option B,
   declined the day it was raised, still available); and finding **G02**, if the
   cross-project bulk tracker change ever matters in practice.

## Known traps

Everything below cost time at least once. The first two are new this session;
the eleven after them came from WP8, and the rest from the work packages before it.

- **Proving an example red on the old code: stash the one file, not the tree.**
  `git stash push lib/…/the_one_file.rb`, run the suite, `git stash pop`. What
  makes this go wrong is stashing too much: a new locale key has to **stay** in
  the working tree, or `I18n.t` returns the "translation missing" string and the
  example fails for a reason that has nothing to do with the code under test —
  which reads as proof and is not. Commit first if the tree is worth protecting.
- **A backgrounded `dev/setup.sh` reports success immediately and means
  nothing.** `nohup dev/setup.sh … &` returns at once, so the shell's exit code
  describes the `&`, not the setup. Read the log file. Both real failures were
  late and quiet: a missing `rsync` (from `dev/sync.sh`, one line) and a missing
  `libpq-dev` (from the `pg` gem build, buried in bundler output). The apt line in
  "Development environment" below installs both — run it *first*.

- **A Deface anchor inside an `<% if %>` renders nothing in the `else` branch,
  and nothing says so.** Core's `issues/_attributes` draws the status control two
  ways, and the second — a plain label — is what `@allowed_statuses.present?`
  being false produces. Anchor on the *branch you need*, both of them if the
  feature has to survive both, and write the assertion so that it can only pass
  in the branch it is about. Read the whole surrounding conditional before
  choosing an anchor.
- **`new_statuses_allowed_to` returns `[]`, not `[current_status]`, when the
  workflow permits nothing.** `statuses << initial_status unless statuses.empty?`
  — the initial status is appended only when something else was found. So an own
  empty workflow, *and* any dead-end status on a stock installation, removes the
  status select from the form entirely rather than emptying it.
- **A query object that takes a parameter it does not use for everything is a
  contract waiting to be broken.** WP8's map took a `tracker:` for its edge query
  and read the status and the dropdown off the issue. Consistent only because one
  caller reconciled them first. If two inputs must agree, take one.
- **`position_of`-style helpers that answer on nil conflate two nils.** A missing
  record can be core's `old_status_id = 0` pseudo-status *or* a row naming a
  deleted status. Tell them apart by the id, not by the record being absent.
- **`Role.anonymous.consider_workflow?` is false; `Role.non_member`'s is true.**
  So "a reader with no workflow role" is an anonymous visitor, not a non-member —
  a non-member of a public project gets *Non member*, which does take part.
- **A `first_or_create!` on `Member` finds the fixture's member and ignores your
  roles.** `users_003` is already a member of `projects_001` as *Developer*. Read
  the fixture, or arrange against the role the user actually holds.
- **`Group.generate!` is a Redmine test helper, not available under RSpec**, and
  a group cannot hold an issue unless `Setting.issue_group_assignment` is on —
  which is cached on the class, so an example that sets it must clear the cache
  again.
- **`WorkflowTransition` validates its status associations**, so a row naming a
  nonexistent status cannot be created through the model. Create it against a
  real status and `delete_all` the status afterwards.
- **A route helper's output is HTML-escaped in the page.** `expect(body).to
  include(some_path)` fails on any path with two query parameters, because `&`
  renders as `&amp;`. Wrap the expectation in `ERB::Util.html_escape`.
- **`rspec` and `rubocop` are not on the PATH until their bundle is installed in
  this container**, and `bundle exec rspec` from the wrong directory reports
  "command not found: rspec" rather than a path error — which reads like a broken
  gem and is a wrong `cwd`.
- **`rm -f some/spec.rb` from the wrong directory silently removes nothing.** Two
  throwaway probe specs survived into a suite run and a RuboCop run that way, and
  the only symptom was a file count one higher than expected (92 rather than 91)
  and an example count one higher. If a number is off by one, look for a probe.

Everything from here down is carried forward from earlier sessions.

- **A new controller action is 403 for everybody until `init.rb` names it in a
  permission.** Administrators included, and the symptom is a forbidden page
  rather than an "unmapped action" error anywhere. `spec/plugin_conventions_spec.rb`
  now asserts structurally that every action of `ProjectWorkflowsController` is
  named by at least one of the two permissions.
- **`to_h` over an unordered `pluck` is a cross-database divergence waiting to
  happen.** Where two rows can share a key, the last one wins — and which one that
  is differs between PostgreSQL and MySQL. Nine green CI cells hide it until a
  database in the field has such a pair. Keep both, or sort before picking.
- **An unscoped `include(user.name)` on a settings page proves nothing.** Core
  renders the Members tab into the same response, so the name is there whatever
  the thing under test says. Scope the assertion with `css_select`.
- **A project whose module is disabled, or which is archived, gives 403 — not
  404.** `authorize` → `Project#allows_to?` → `deny_access` → `render_403`. Only a
  finder that cannot match its parameter gives 404.
- **`Set#flatten` flattens nested Sets, not the Arrays inside one.**
  `Set[[1, 2]].flatten` is still a Set of one Array, so a `reject(&:zero?)` after
  it raises `NoMethodError` on `Array`.
- **A query-count example can measure lazy fixture loading.** A memoised
  `let(:trackers_list) { [trackers(:x), trackers(:y)] }` referenced for the first
  time *inside* the counted block adds two SELECTs to the first iteration and none
  to the second — which looks exactly like an N+1 and is not. Force the lists
  before counting.
- **A JavaScript scenario inherits the previous one's state.** The undo stack
  lives for the life of a page, so `dev/check-bulk-js.mjs` re-evaluates the whole
  `javascript_tag` block per scenario. The first version of those checks passed
  vacuously on a stack an earlier scenario had left behind.
- **`say_with_time` prints a row count only if its block returns an Integer.**
  `execute` returns an adapter result object, so a migration that wraps a raw
  `INSERT ... SELECT` prints the elapsed time and nothing else. A README that
  promises the operator a number has to be checked against the migration.
- **Redmine's plugin migration task defaults to *development*.** It is
  `=> :environment`, so `rake redmine:plugins:migrate` with no `RAILS_ENV`
  migrates the wrong database and prints output that looks like success. Every
  migrate command in user-facing documentation needs `RAILS_ENV=production`, and
  CI cannot catch its absence because CI sets `RAILS_ENV: test` job-wide.
- **Migrations reverse in the order they were applied.** `VERSION=0` runs 005's
  down, then 004's, and so on — so `project_workflow_scopes` is dropped *before*
  migration 001 deletes the project rules. Do not describe a down sequence from
  reading one migration.
- **A documented query count is worth measuring, not estimating.** `docs/design.md`
  said the settings tab costs four collection queries; it is six. The
  constant-cost property was right and the number was not — so state the property
  and measure the number.
- **Redmine core already has an issue-form status help icon and modal.** Do not
  build a second one. `issues/_attributes.html.erb`,
  `label_open_issue_statuses_description`,
  `showModal('issue_statuses_description')` and
  `issues/_issue_status_description` — byte-identical in 5.1, 6.1 and 7.0 apart
  from `sprite_icon` arriving at 6.0. `IssueStatus#description` is a real core
  column on all three.
- **A `rubocop -a` autocorrect can *create* the offence you then grandfather.**
  `Layout/MultilineOperationIndentation` re-aligned a 101-character line in core's
  copied body to 125, and the todo entry written straight afterwards explained it
  away as "keeping core's shape" — the exact opposite of what had happened. Read
  what an autocorrect did before annotating what it left.
- **Redmine 6.1 emits a `to_time` deprecation warning from its own `time_tag`**
  whenever `@project` is set, via `User#time_to_date`. WP6's audit line is the
  first thing in the plugin to call `authoring`, so the warning now appears once
  in the 6.1 suite output. It is core's, not the plugin's; core hits the same path
  on `repositories/_changeset`. Do not chase it.
- **`rubocop -a` over a grandfathered codebase is a 244-offence diff through the
  writers and the query services.** Safe cops only, and run the whole suite
  afterwards on more than one version before believing it. Then regenerate the
  todo and *annotate* it: a generated list cannot tell debt from a decision.
- **`git checkout -- .` in a scratch script destroys uncommitted work.** It
  restores to **HEAD**, not to what you had. **Commit first, then run revert
  experiments** against the commit, and never let such a script touch anything
  but the file it reverted.
- **Deface renames an attribute whose value contains ERB.**
  `style="width:<%= ... %>"` is matched as `td[data-erb-style]`, not `td[style]`.
  A selector that does not match produces no error and no output.
- **A `<select>` that acts on its own `change` event is an accessibility trap.**
  Arrow keys on a closed select fire `change` per step, so a keyboard user applies
  every value on the way to the one they wanted. This is why the row and column
  actions, and the undo, are links.
- **Redmine's administration screens are behind sudo mode, in the suite too.** A
  spec that logs in as administrator gets the password form instead of the page
  unless it also sets `@request.session[:sudo_timestamp] = Time.now.to_i`.
- **`Setting.plugin_<id>` is cached on the class.** A spec that writes it needs
  `after { Setting.clear_cache }`.
- **`dev/sync.sh` deletes what it did not copy.** A throwaway spec written
  directly into the host's `plugins/` directory is gone after the next sync.
- **`dev/run.sh` runs the whole spec directory even when given one file.** To run
  one file, call `bundle exec rspec plugins/redmine_project_workflows/spec/<path>`
  inside the host after `dev/sync.sh`.
- **The Bash working directory persists between calls — sometimes.** A `cd` into
  `.redmine/<host>` for one command leaves the next one there, and `git` then
  answers for Redmine's checkout rather than the plugin's, and `dev/run.sh` is not
  on the path. Prefix with an explicit
  `cd /home/user/redmine_project_workflows &&`.
- **Redmine's stylesheet removes the focus outline only on form controls and on
  `button.tab-left`/`button.tab-right`** — never on `a`, on 5.1, 6.1 or 7.0.
- **The plugin ships no stylesheet.** A class on a plugin element is a hook for a
  theme, not colour — so the words have to carry the whole meaning, and markup
  structure (a block element) is the only way to stop items crowding onto one
  line.
- **`Array(relation).size` copies the records; `relation.size` does not.**
- **Never extend `project_settings_tabs` with `ProjectsHelper.prepend`.** A
  neighbouring plugin's alias chain resolves through `ProjectsHelper.ancestors`,
  copies the prepended method, and loses its `super` — core's own tabs vanish and
  every settings page raises `NoMethodError`. `ProjectsController.helper(Mod)`
  instead: beside `ProjectsHelper`, never inside it.
- **Redmine renders every settings tab's partial on every visit.** `showTab` only
  hides and shows what is already in the page, so a tab's content has to be cheap.
- **`ProjectsController#update` calls the `settings` *method* and then renders the
  settings view**, so a `before_action` would not run on that path. A helper
  sidesteps the question.
- **A tab entry's `:action` may be an action hash, not only a permission name.**
  That is how a tab is made visible to holders of *either* of two permissions.
- **A Redmine path helper uses `Project#to_param`, which is the identifier** —
  except in a form built with `form_tag({}, method: :get)`, which reuses the
  request's own path parameters and carries the **id**. Both appear in one page,
  so use the route helper in the expectation.
- **A spec can be passing on another spec file's fixtures.** `spec/models/` and
  `spec/services/` specs that create an `Issue` need `:enumerations`;
  `project_statuses_spec.rb` needs `:projects_trackers`.
- **A reused test database hides a missing fixture.** Two hosts disagreeing is a
  signal, not a flake.
- **Rails' `include_all_helpers` does not reach a plugin's `app/helpers`.** Name
  it with `helper MyHelper`; for a view rendered by a *core* controller, do it from
  the patch's `self.prepended(base)`.
- **A module mixed into a controller must not have public methods.** Every public
  instance method of a controller is an action.
- **Redmine 5.1's `MenuManager::Mapper#push` is not idempotent.** Guard with
  `Redmine::MenuManager.map(:admin_menu).exists?(...)`.
- **`dev/setup.sh` does not drop the test database.** Deleting `.redmine` is not
  the same as starting clean.
- **A CI run marked "cancelled" is usually the concurrency group, not a failure.**
  Read the *head's* run.
- **`rails runner` without `RAILS_ENV=test` boots development and dies on a
  missing `listen` gem.** Every command against a host needs `RAILS_ENV=test` in
  the *same* invocation — shell exports do not survive between tool calls.
- **PostgreSQL rejects `ORDER BY` on a column that `SELECT DISTINCT` does not
  select.** `reorder(nil)` first.
- **`.or` must come before `.distinct`, not after.**
- **MariaDB 10.11 rejects a table alias in a single-table `DELETE`.** PostgreSQL
  and MySQL 8.4 both accept it, so a statement can pass six of nine CI cells.
- **`mariadb -e "…" | head` reports `head`'s exit status, not MariaDB's.**
- **MariaDB *can* be installed in this container** — `apt-get install -y
  mariadb-server libmariadb-dev`, then `mariadbd --user=mysql
  --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock` in the background, a
  `redmine` user with `GRANT ALL`, and `dev/setup.sh <branch> mysql <ruby>`.
- **A unique index cannot enforce a key with a nullable column** on any of the
  three supported databases.
- **A cache built from the rules is not invalidated by the scope writer.**
  `Resolver.reset_cache!` clears both request caches, but it has to be *called*.
- **InnoDB refuses to drop the last index with a foreign key's column leftmost**
  (MySQL error 1553). Migration 005 checks for its replacement first.
- **Rendering from a Redmine `before_action` answers before `require_admin`.**
  Core's `WorkflowsController` declares its finders before the authorization
  callback. Collect and let the action decide. `ProjectWorkflowsController` is the
  other way round on purpose — `authorize` is declared first, so *its* finder may
  render.
- **A migration's effect is invisible to the process that ran it.**
- **PostgreSQL will not cast a text literal to a timestamp inside a `SELECT`
  list.** The backfill uses `CURRENT_TIMESTAMP`.
- **A spec that fails while creating a project poisons the database.** To clear:
  `DELETE FROM projects_trackers WHERE project_id NOT IN (SELECT id FROM projects)`
  — without a table alias, or MariaDB refuses.
- **A new project already has `Setting.default_projects_modules` enabled.** Guard
  with `module_enabled?`.
- **`Project#archive!` is private; `Project#archive` is not.**
- **Redmine's I18n applies only the `one`/`other` plural forms to Polish.**
- **A YAML value containing `": "` needs quoting.** `spec/locales_spec.rb` catches
  it, on every host.
- **`Rails.application.config.to_prepare` in `init.rb` never runs.** Call
  `apply_patches` in the body of `init.rb` instead.
- **A plugin's permissions accumulate on every code reload in development.**
  Harmless, and true of every Redmine plugin.
- **Never let `spec/spec_helper.rb` apply the patches itself.**
- **Redmine 7.0 has no `request_store`.** Use `RedmineProjectWorkflows::Current`,
  and reset it in specs.
- **The plugin is copied into the Redmine host, not symlinked.**
- **Run the migration checks before the suite.** `maintain_test_schema` reloads
  `db/schema.rb` when the suite starts and wipes the plugin's migration
  bookkeeping, after which `VERSION=0` silently does nothing.
- **`render_404` does not abort the action.** It renders and returns `false`. In a
  `before_action` the *chain* does halt, so one `render_404` as the last statement
  of a callback is safe; two are not.
- **`User#roles_for_project` caches memberships on the object.**
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.**
- **`Naming/MemoizedInstanceVariableName` fires on a method whose body ends in
  `@other ||= ...`** — and on `find_statuses`, where `@statuses` is the name the
  view reads, so the cop's own fix would empty the matrix.
- **`.contextual` is floated, so it has to come *before* the heading.**
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** What changed at 6.0
  is that CSS icons became SVG sprites — five things the plugin renders go through
  `RedmineProjectWorkflows::VersionHelper`. `app/helpers/workflows_helper.rb` and
  `app/views/workflows/_form.html.erb` are byte-identical between 6.1 and 7.0 and
  differ from 5.1 only in how the toggle link is written;
  `issues/_attributes.html.erb` differs only in `sprite_icon`.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`.
- **`safe_attributes=` sets `project_id` before `tracker_id`**, on purpose. This
  is why finding G03 is not a two-line fix.
- **Rails casts oddly in `where(id:)`.** `Project.where(id: ['1e5'])` returns
  project 1. Check the *shape* of an id (`/\A\d+\z/`) before querying, or
  intersect against an already-loaded list.
- **A workflow rule can make an issue invalid.** A generic `due_date required`
  rule makes `Issue.create!` fail in a spec that arranges the rule first.
- **`rails-ujs` is loaded on all three versions**, so `link_to ..., method: :post,
  data: { confirm: ... }` works. The row and column actions and the undo do not
  depend on it — they are `link_to_function` with an `onclick`.

## Development environment (rebuild from scratch in a fresh session)

```bash
# packages the container does not have
apt-get update -qq && apt-get install -y rsync libpq-dev

# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (about four minutes each; run them in
# the background in parallel)
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/setup.sh 6.1-stable postgresql 3.3.6
dev/setup.sh 7.0-stable postgresql 3.3.6

# the migration gates, BEFORE the suite, per host. RAILS_ENV=test has to be in
# the same invocation.
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0)
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows)
dev/check-backfill.sh .redmine/7.0-stable-postgresql 3.3.6

# sync the working tree and run the suite
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-postgresql

# one spec file only (dev/run.sh always runs the whole directory)
dev/sync.sh .redmine/7.0-stable-postgresql
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rspec \
  plugins/redmine_project_workflows/spec/controllers/project_workflows_controller_spec.rb)

# the JavaScript gate the suite cannot run (node only, not in CI)
node dev/check-bulk-js.mjs

# lint (rubocop's binaries are not on PATH by default in this container)
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle install
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant.

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

There is no WP9, and CI is green on the head. So the honest answer to "carry on"
is that the plan is finished and the branch is waiting on Jan — say so rather
than inventing work. The "Exact next step" section above lists what he could ask
for next if he wants more.
