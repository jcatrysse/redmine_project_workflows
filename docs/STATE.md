# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP7** are **done**. **WP8** is the only one
  left, and Jan asked for it in a session of its own. All of them are in
  `docs/implementation-plan.md`, which runs WP0..WP8.
- **What exists:** the plugin at **0.1.0** — the scope model (WP1), the core
  seams (WP2), the per-scope summary page and inventory (WP3), the Workflow tab
  in project settings behind two permissions (WP4), row and column actions on
  every transition matrix (WP5), an audit trail, a project-versus-generic
  comparison screen and a counter with undo (WP6), and as of this session the
  documentation, locale and release pass (WP7).
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. It overrides whatever name the
  environment gives a session. **Pull before you start** — a previous session
  found the local branch 36 commits behind the remote after checkout, and worked
  against WP4-era files for one tool call before noticing.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** **one**. WP7 raised the declared minimum Redmine version from
  5.0 to 5.1; the options and a recommendation are in `docs/DECISIONS.md` under
  "Open — for Jan". Not urgent, and it is in place already. WP8's renderer
  question was answered **C** and has moved up.
- **Open findings:** **2**, both left deliberately: G02 (a cross-project bulk
  tracker change is two queries per project where core is one — WP6 confirmed
  WP2's reasoning rather than overturning it) and G03 (`Issue#project=`, which
  behaves as core does). F11 is **fixed** by WP7 and carries a `Resolution:` line
  saying what it got right and what another package had already done. One more is
  wont-fix (G04). `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` lists
  them, plus one line from `TEMPLATE.md` that is not a finding.
- **`spec/characterization/`:** still **gone**, since WP3. The convention stands
  and is written down in `dev/README.md`: a defect that is found but not yet
  fixed is pinned there first.

## What this session produced

### WP6 — compare, audit, undo

**Who last changed this workflow.** The scope table has carried
`created_by_id`/`updated_by_id` since WP1 and nothing maintained them on the
ordinary edit path: `ScopeWriter.ensure_scopes`, which every project matrix save
goes through, deliberately left an existing scope alone. `touch_scopes` is the
stamp, called *before* the create so a row inserted by the same call is not
stamped twice; the copy screen stamps too. The two halves stay apart on purpose —
`created_*` records who decided the project runs its own workflow, `updated_*`
who last changed the rules. The sentence on screen is core's own `authoring`
helper with `label_updated_time_by`, so it needed **no locale key of its own**.

**A project's workflow against the generic one.** `Services::WorkflowComparison`,
a `compare` action, a screen, and links from the settings tab, either matrix
header and the administration inventory — all three built by one helper. The unit
of comparison is **core's grid, not the stored row**: `WorkflowsController#edit`
partitions transitions with `reject { author || assignee }`, `select(&:author)`
and `select(&:assignee)`, so a row with both flags set is in two grids at once.
Field permissions carry each side's rules as a **list**, because two rows for the
same (status, field) that disagree are possible and picking one would make the
page depend on the order the database returned them.

**A counter and an undo.** WP5's actions already changed only the screen; nothing
on the page said so. There is now a region above the matrix with the count, the
workflow rules it costs, an Undo and the sentence that nothing is saved until
Save is pressed. The undo is a **stack** and restores the value each control held
*before the action* — not the value the page was opened with, which is what "no
change" already means. No new Deface anchor, so the **INV-9 count stays at
thirteen in eleven files**.

### WP7 — documentation, locales, release

Four of six bullets were real work. **Two were already true and the plan says so
rather than claiming them:** the terminology (*Generic workflow*, *Own workflow*,
*Inherits the generic workflow*) is what WP3, WP4 and WP5 used as they went, in
all eight locale files; and version-conditional code was already behind
`VersionHelper`.

- **The README** gained *What to know before you install it* (F11, and more than
  it listed), a section on what a selection of several projects does when you save
  — F11's one remaining gap, and the case that writes the most rules from one
  click — and *Upgrading and uninstalling*, which is the part with teeth: what the
  backfill does, and that `VERSION=0` **deletes every project-specific rule**
  before dropping the column, deliberately, because dropping the column with
  those rows still there would leave stock Redmine reading each of them as a
  *generic* rule.
- **0.1.0**, with a CHANGELOG that reads as a release rather than a diff, and the
  entries reordered newest-first.
- **The declared minimum moved from Redmine 5.0 to 5.1.** Nothing had ever tested
  5.0 and the README said so. Logged as an open choice with the default in place.
- **`.rubocop_todo.yml`: 198 offences in 21 files down to 48 in 8**, annotated by
  hand rather than generated and left. The file's own header names the three
  groups the rest falls into: the four patch files whose method bodies are core's
  (refactoring them for a metric destroys the property that lets you diff them
  against a real checkout), `insert_all`/`update_all` in the writers (INV-2 — the
  writer *is* the validation), and three single offences where the cop's fix would
  be wrong. One was worth fixing rather than excluding:
  `TransitionWriter.transition_row` took seven positional parameters ending in two
  booleans, and is now keyword arguments.
- **A new gate:** `init.rb`'s version and the newest `CHANGELOG.md` heading are
  asserted to agree. Reverting the version bump alone left the suite green, which
  is exactly the drift worth catching.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 484 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 484 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 484 examples, 0 failures |
| RuboCop | 82 files, no offences. The todo is 48 offences in 8 files, down from 198 in 21, and every remaining entry carries a reason |
| `node dev/check-bulk-js.mjs` | **32** checks, all ok (was 16) |
| Migration reversibility up → 0 → up | clean on 7.0, run **before** the suite |
| `dev/check-backfill.sh` | passes on 7.0 + PostgreSQL |
| Locale parity | eight files, **74** keys each (was 53) |
| Independent review | run in a **fresh subagent**, twice — for WP6 and for WP7. First session where the mechanism was available. Both sets of findings are fixed; see below |
| CI | run **45 green on all nine cells plus RuboCop** for commit `f65dc48`. Runs 36 through 43 were green too; **44 reads "cancelled" because 45 superseded it** — that is the concurrency group, not a failure. The runs for the two commits after `f65dc48` were still in flight when this file was written — **check the head's run first** |
| New specs against the old code | measured, twelve-plus-five-row table below |

**The "fails on the old code" checks, run rather than assumed.** Each was done by
putting one file back to its state before the commit and leaving the rest in
place, against the full suite on 7.0. The working tree was **committed first**, so
the restore afterwards is exact.

| Reverted | Fails |
| --- | --- |
| `services/scope_writer.rb` (the audit stamp) | 5 |
| `services/inventory_query.rb` (the audit pair in the cell) | 19 |
| `helpers/project_workflows_helper.rb` | 37 |
| the inventory's index view | 1 |
| the settings tab partial | 1 |
| `services/workflow_comparison.rb` | the suite does not load |
| `views/project_workflows/compare.html.erb` | 6 |
| `init.rb` (the permission mapping) | 10 |
| `config/routes.rb` | 29 |
| `_matrix_header.html.erb` | 1 |
| `_bulk_undo.html.erb` | 22 |
| `_matrix_note.html.erb` | 2 |
| the review fixes: `workflow_comparison.rb` / `scope_writer.rb` | 8 / 1 |
| the review fixes: controller / view / helper | 3 / 3 / 3 |

Two WP7 changes revert **without** failing, and that is the right answer:
`init.rb`'s version bump (nothing asserted it — which is why WP7 added the
assertion, and setting the version to 0.9.9 now fails with *"init.rb declares
0.9.9; CHANGELOG.md's newest entry is 0.1.0"*) and `transition_row`'s conversion
to keyword arguments, which is a pure refactor the existing writer specs already
cover.

### What the two independent reviews caught

Worth reading before the next one, because the pattern repeats.

**WP6.** Seven of thirteen findings were real, and the most important was
**latent, not red**: the field-permissions comparison built its map with `to_h`
over an unordered `pluck`, so two rows for the same (status, field) that disagree
made the page depend on which row came back last — the same installation
comparing differently on PostgreSQL and on MySQL, with nine green CI cells hiding
it. Also: the copy screen never stamped the audit columns; the compare page
counted distinct keys where the settings tab counts rows; two `COUNT(*)` queries
were redundant; a difference can name a field no project screen can change and
nothing said so; the 403/404 documentation was wrong in three places; and two new
specs passed for the wrong reason. One finding was declined with a reason.

**WP7.** No blockers, and the reviewer confirmed by *running* it that both
headline lint numbers were true (198 in 21 files before, 50 in 8 after — 48 once
its own findings were fixed) and that
none of the 244 autocorrected offences changed behaviour — it walked every
semantically-loaded rewrite, including `each_value` on
`ActionController::Parameters` across all three Rails versions. Six findings were
real, and **three were in the one section that tells an operator how to destroy
data**: the uninstall instruction described the down migrations in the wrong
order (the scope table goes *before* the rule delete — migrations reverse in the
order they were applied), it omitted `RAILS_ENV` from every migrate command, and
Redmine's plugin task defaults to **development**, so the realistic outcome was an
operator destroying nothing in production while watching migration output say
otherwise. Also: the plugin's biggest install-time behaviour change — routing
core's own `replace_transitions` / `replace_permissions` through the writers,
which narrows what a *generic* save accepts on every installation — was in
neither the README nor the CHANGELOG; a `.rubocop_todo.yml` annotation excused a
long line the autocorrect had itself created; another filed
`workflow_rule_patch.rb` under INV-2 when that file uses `connection.insert` and
is not a writer at all; and F11 ended up marked both fixed and open. All six are
fixed.

The QA pass caught one before the reviewer: the draft README said the backfill
reports how many scopes it created. It does not — `say_with_time` prints a row
tally only when its block returns an integer, and a raw `INSERT ... SELECT`
returns the adapter's result object.

## Exact next step

**WP8** — the status help and the transition map on the issue form. Jan asked for
it in a session of its own, and the renderer question is settled: **option C**,
the local "from here" view, a `table.list` of *from → to → condition*, **no
drawing**. `docs/implementation-plan.md`'s WP8 section is the route and
`docs/design.md`'s "Telling the end user what the workflow is (WP8)" is the
target. Read both before starting; the three things that decide whether it is any
good are already written down there:

1. **Do not rebuild the status help icon.** Redmine core already ships it, on 5.1,
   6.1 and 7.0 — `issues/_attributes.html.erb` renders an `icon-help` link
   opening `#issue_statuses_description`, a `<dl>` of status name and
   `IssueStatus#description`. It lists `@allowed_statuses`, which is
   `Issue#new_statuses_allowed_to`, the method this plugin replaces in full, so it
   is **already** describing the project's own effective workflow. WP8's job there
   is specs (INV-4: it must never name a status only another project's rules
   reach) and a README paragraph pointing administrators at *Administration →
   Issue statuses → Description*, because the icon is invisible until somebody
   fills those in.
2. **The map must not contradict the dropdown.** `new_statuses_allowed_to` also
   drops closed statuses for a blocked issue or one with open subtasks, open ones
   for a subtask of a closed parent, and filters the author and assignee variants
   by identity. An edge the map shows and the dropdown withholds carries the
   reason — core's own `transition_warning` sentence where core has one.
3. **Lazily, from an action of its own.** The issue form gets a link and runs no
   extra query; the resolver's hot path is untouched (G6).

**Check the head's CI run first.** Run 45 is green on all nine cells for
`f65dc48`; the two commits after it (STATE.md, and the WP7 review fixes) were
still in flight when this file was written. Everything in them ran locally on all
three Redmine versions first, and neither changes behaviour — the review fixes are
prose, one line rewrap and one comment — but read the *head's* run rather than the
newest completed one. A run reading "cancelled" is the concurrency group
superseding it after the next push.

## Known traps

Everything below cost time at least once. The first fifteen are new this session.

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
