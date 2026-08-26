# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0, WP1, WP2, WP3, WP4 and WP5 are **done**. WP6 is next and
  has not been started. WP0..WP7 are specified in `docs/implementation-plan.md`.
- **What exists:** the plugin as shipped in 0.0.3, the WP0 repairs, the scope
  model from WP1, the core seams from WP2, WP3's per-scope summary page and
  inventory, WP4's Workflow tab in project settings, and — as of this session —
  **row and column actions on every transition matrix**, plus the plugin's first
  setting and the settings screen that implies.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/docs-review-9ny8n3`, which the environment had prescribed; nothing was
  committed there.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** one, not urgent, recorded in `docs/DECISIONS.md` under
  "Open — for Jan": whether the **field-permissions** matrix should get row and
  column actions too. It has none today and never had core toggles to repair; its
  cells are four-valued rather than yes or no. We continued with A, leave it.
- **Open findings:** 3, down from 4. `external` F11 (the README understates the
  operational risks, WP7), G02 (a cross-project bulk tracker change is an N+1,
  WP6) and G03 (`Issue#project=`, examined in WP4 and deliberately left as core
  behaves). `claude` F06 is now **fixed** — see below; its `Resolution:` line says
  what the finding got half right. One more is marked wont-fix (G04).
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` lists them, plus one
  line from `TEMPLATE.md` that is not a finding.
- **`spec/characterization/`:** still **gone**, since WP3. The convention stands
  and is written down in `dev/README.md`: a defect that is found but not yet
  fixed is pinned there first.

## What this session produced

**A whole row or column of a transition matrix, in one click.** Every row and
every column header now carries three actions next to its name — **Yes**, **No**
and core's own *(No change)* — on the administration screens and on a project's
own matrix alike, because both render core's `workflows/_form` partial.

**Finding F06 was half right, and the half that was wrong mattered.** The finding
said that giving a mixed cell the same CSS classes as a checkbox cell would make
core's own row and column toggles reach it. The classes were indeed missing and
are now there — but core's toggle selects on
`input[type=checkbox]:not(:disabled).new-status-N`, and nothing of that shape can
ever match a `<select>`, whatever it is called. So core's toggle is left exactly
as it was, and the plugin adds actions of its own that select on the class alone
and therefore reach both kinds of control. The classes are what lets one selector
serve both, which is why they were still worth adding.

**Three actions rather than a toggle**, because toggling is not the same as
setting and setting a whole row to No is the case with the clicking in it.
*(No change)* restores the value the control was rendered with — a mixed cell's
own no-change option, a checkbox's `defaultChecked` — which is exactly what a
mixed cell means. It is offered only where a cell can hold it: a project matrix
is one workflow per cell by construction, so a third state there would name
something the matrix cannot be in.

**Links, not a select that applies on `change`.** A select acting on its own
change event fires once per step when a keyboard user arrows through it, so it
would apply values nobody asked for and prompt for confirmation on the way past.
Links are one tab stop each, they keep the browser's own focus ring — Redmine's
stylesheet removes the outline on form controls and on two tab buttons, never on
`a`, on any supported version — and each carries the whole sentence in `title`
and `aria-label`. The function they call is written once per page, from whichever
header renders first, because the transitions page renders the same grid three
times.

**How much a click is about to write, said out loud.** Above the matrix, on both
administration screens, a sentence giving the number of workflows one cell stands
for and explaining *(No change)*. It comes from the scope panel's anchor rather
than one of its own, and unlike the panel it does not wait for a project to be
selected: core's own no-change cells appear for a selection of several trackers or
roles alone. A project matrix says nothing, because one cell there is one
workflow, and the half of the legend that describes the row and column actions is
left off the field-permissions page, which renders core's no-change cells but has
no such actions.

**And a confirmation, behind the plugin's first setting.** *Ask before a row or
column action changes more than* — 50 workflow rules by default, 0 to ask every
time, under **Administration → Plugins → Project Workflows → Configure**. The
browser counts only the controls whose value would actually change and multiplies
by the workflows one cell stands for, so an action that changes nothing never
asks. The same number is the helper's fallback for a settings hash an
administrator saved before the key existed, and a spec asserts the two agree.

**One cell size, one owner.** `workflow_permissions_matrix_size` — the plugin's
replacement for core's `@roles.size * @trackers.size` — is now a one-line
delegation to `BulkActionsHelper#project_workflow_selection_size`, which the row
and column actions ask as well. A cell and the actions on it can no longer
disagree about whether that cell is mixed.

**Two more Deface overrides: thirteen in eleven files** (INV-9), counted in
`CLAUDE.md`, `docs/design.md` and the spec's own comment. Both anchor on a header
*cell* of core's `workflows/_form` — the only `td` with a style attribute and the
only one with `class="name"` — rather than on the toggle expression, which 5.1
writes as a bare `link_to_function` and 6.0 and later as
`toggle_checkboxes_link`. Deface renames an attribute whose value contains ERB,
so the column header is matched as `td[data-erb-style]`.

**The gate the suite cannot run, run anyway.** The actions are JavaScript and
this repository has no JS test harness, which is the main reason the function has
no event wiring of its own. `dev/check-bulk-js.mjs` closes the gap outside the
suite: a hand-built DOM, the function extracted from the partial, and sixteen
checks — both kinds of control, the disabled diagonal left alone, *(No change)*
as a restore, a control without that option untouched, the count in the
confirmation, a refused confirmation changing nothing, a threshold of zero, and
an action that would change nothing neither asking nor firing. It needs node and
nothing else, it is documented in `dev/README.md`, and it is **not** in CI.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 419 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 419 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 419 examples, 0 failures |
| RuboCop | 80 files, no offences |
| `zeitwerk:check` | "All is good!" on 5.1, 6.1 and 7.0 |
| `node dev/check-bulk-js.mjs` | 16 checks, all ok |
| Migration reversibility up → 0 → up | clean on 7.0, run **before** the suite. WP5 changes no migration |
| Backfill (`dev/check-backfill.sh`) | passes on 7.0 + PostgreSQL |
| Locale parity | eight files, 53 keys each (was 45) |
| Independent review | run in this context rather than a fresh one — see "Known traps" |
| New specs against the old code | see below |
| CI | **run 33 is green on all nine cells plus RuboCop**, on the branch head `a6a1508` — Redmine 5.1, 6.1 and 7.0 × PostgreSQL, MySQL and MariaDB. Run 32 was green as well, on the commit before it. (A run reading "cancelled" is the concurrency group superseding it after the next push — not a failure, and easy to misread.) |

**The "fails on the old code" checks, run rather than assumed.** Each was done by
putting one thing back and leaving the rest of WP5 in place, against the full
suite on 7.0:

| Reverted | Fails |
| --- | --- |
| the two Deface overrides on `workflows/_form` | 5 examples |
| the classes on a mixed cell | 1 |
| the note above the matrix | 2 |
| the plugin setting in `init.rb` | 38 |
| the guard that offers "no change" only where a cell can hold it | 2 |
| the cell size computed as core does, ignoring the scopes | 8 |
| the settings partial | 2 |

The 35 new examples cover the two anchors (each with an assertion only it can
satisfy — `.new-status-N` for the column action, `.old-status-0` for the row),
the classes on both kinds of cell, the cell-size arithmetic including a view that
set no lists at all, the three actions and their titles, "no change" offered and
withheld, the function written once per page, the threshold read from the setting
and its four fallbacks, the note shown and withheld on both administration
screens and on a project matrix, the actions absent from a read-only project
matrix, and the settings screen: the field, a save, a saved value shown back,
administrator-only and anonymous.

## Exact next step

Start **WP6** from `docs/implementation-plan.md`: compare, audit, undo. Read the
work package first — in outline it is a comparison of a project's workflow with
the generic one, the audit columns the scope table already carries, and an undo
before save. Finding **G02** (a cross-project bulk tracker change is an N+1) is
scheduled for WP6 and should be read with it; `docs/DECISIONS.md` records why WP2
left it alone, and that reasoning is what WP6 has to overturn or confirm.

CI is green for WP5 on all nine cells, so there is nothing to check first this
time — start with the work package.

## Known traps

Everything below cost time at least once. The first nine are new this session.

- **`git checkout -- .` in a scratch script destroys uncommitted work.** A
  "revert one thing and see the suite go red" script that restores with
  `git checkout` restores to **HEAD**, not to what you had. Three files' worth of
  WP5 was silently rolled back that way, and a second script then made its
  backup from the damaged tree. **Commit first, then run revert experiments**
  against the commit; and never let such a script touch anything but the file it
  reverted.
- **Deface renames an attribute whose value contains ERB.**
  `style="width:<%= ... %>"` is matched as `td[data-erb-style]`, not `td[style]`.
  A selector that does not match produces no error and no output, so the anchor
  looked plausible and simply did nothing until the spec asked for it.
- **A `<select>` that acts on its own `change` event is an accessibility trap.**
  Arrow keys on a closed select fire `change` per step in every major browser, so
  a keyboard user applies every value on the way to the one they wanted. This is
  why the row and column actions are links.
- **Redmine's administration screens are behind sudo mode, in the suite too.**
  `Redmine::Configuration['sudo_mode']` is true by default, and
  `SettingsController` declares `require_sudo_mode :index, :edit, :plugin`. A
  spec that logs in as administrator gets the password form instead of the page
  unless it also sets `@request.session[:sudo_timestamp] = Time.now.to_i`.
- **`Setting.plugin_<id>` is cached on the class.** A spec that writes it needs
  `after { Setting.clear_cache }`, or the next example inherits the value even
  though the row was rolled back.
- **`dev/sync.sh` deletes what it did not copy.** A throwaway spec written
  directly into the host's `plugins/` directory is gone after the next sync.
  Write it in the working tree, or copy it in again after every sync.
- **The bulk script mentions `no_change` whatever the page offers.** An assertion
  that "no change is not offered" has to ask about
  `data-project-workflow-value="no_change"`, not about the string in the page.
- **Redmine's stylesheet removes the focus outline only on form controls and on
  `button.tab-left`/`button.tab-right`** — never on `a`, on 5.1, 6.1 or 7.0. So a
  link-based control keeps a visible focus ring with no CSS of the plugin's own.
- **`Array(relation).size` copies the records; `relation.size` does not.**
  `ActiveRecord::Relation#to_a` returns `records.dup`, and the matrix asks for the
  cell size once per cell — 126 copies of every project on the installation for a
  selection of "all".
- **Never extend `project_settings_tabs` with `ProjectsHelper.prepend`.** A
  neighbouring plugin's alias chain resolves the name through
  `ProjectsHelper.ancestors`, copies the prepended method, and loses its `super`
  — core's own tabs vanish and the settings page raises `NoMethodError` for every
  project. `ProjectsController.helper(Mod)` instead: beside `ProjectsHelper`,
  never inside it. This is a row in CLAUDE.md's forbidden-constructs table.
- **Redmine renders every settings tab's partial on every visit.**
  `showTab` only hides and shows what is already in the page, so a tab's content
  is built whether or not anybody clicks it, and it has to be cheap.
- **`ProjectsController#update` calls the `settings` *method* and then renders
  the settings view.** So a `before_action` would not run on that path. A helper
  sidesteps the question entirely, which is why the tab's rows are one.
- **A tab entry's `:action` may be an action hash, not only a permission name.**
  `User.current.allowed_to?` takes either. That is the way to make a tab visible
  to holders of *either* of two permissions without inventing a third.
- **A Redmine path helper uses `Project#to_param`, which is the identifier.**
  `/projects/ecookbook/...`, not `/projects/1/...` — except in a form built with
  `form_tag({}, method: :get)`, which reuses the request's own path parameters
  and therefore carries the **id**. Both appear in one rendered page, so a loose
  `%r{/projects/\d+/workflow/...}` assertion passes against the wrong form. Use
  the route helper in the expectation.
- **`spec/models/project_statuses_spec.rb` was passing on another file's
  fixtures.** A spec that does not declare `projects_trackers` sees whatever the
  last file that did left behind, and `#rolled_up_statuses` walks a whole project
  tree, so one undeclared row on a subproject changes the answer. eCookbook has
  four descendants; OnlineStore is a leaf, which is what makes "the generic
  status is absent" assertable at all.
- **`git` in a Bash call may not be the repository you think.**
  `.redmine/<version>-<db>` is a git checkout of Redmine. A `cd` earlier in a
  compound command does not reliably persist to the next tool call — and
  sometimes it does, which is worse. Use absolute paths, and check
  `git stash list` in `/home/user/redmine_project_workflows` before believing
  anything is lost.
- **`dev/run.sh` runs the whole spec directory even when given one file.** It
  passes the directory *and* your argument to rspec. To run one file, call
  `bundle exec rspec plugins/redmine_project_workflows/spec/<path>` inside the
  host after `dev/sync.sh` — and remember `dev/sync.sh` is what copies the
  working tree in, so an edit is invisible to the host until it runs.
- **`Naming/MemoizedInstanceVariableName` fires on a method whose body ends in
  `@other ||= ...`.** Splitting the fallback into its own predicate-ish method
  reads better anyway.
- **`.contextual` is floated, so it has to come *before* the heading.** Core
  always renders it first. Deface's `surround` with `<%= render_original %>`
  places content on both sides in one override, and raises if the placeholder
  goes missing.
- **A spec can be passing on another spec file's fixtures.** `spec/models/` and
  `spec/services/` specs that create an `Issue` need `:enumerations` for the
  default priority. Before believing a green suite, ask which file loaded the
  fixture you are relying on.
- **A reused test database hides a missing fixture.** Two hosts disagreeing is a
  signal, not a flake.
- **Rails' `include_all_helpers` does not reach a plugin's `app/helpers`.** It is
  built from the host application's helper paths only, so a plugin helper module
  has to be named with `helper MyHelper` even though Zeitwerk autoloads it. For a
  view rendered by a *core* controller, do it from the patch's
  `self.prepended(base)`.
- **A module mixed into a controller must not have public methods.** Every public
  instance method of a controller is an action. `WorkflowsControllerProjectSelection`
  and `ProjectsControllerPatch`'s loader are private for that reason — and a
  helper module must therefore be `helper`-ed into a controller, never `include`-d.
- **Redmine 5.1's `MenuManager::Mapper#push` is not idempotent.** 6.1 and 7.0
  reject an existing item of the same name first; 5.1 does not. Guard with
  `Redmine::MenuManager.map(:admin_menu).exists?(...)`.
- **`dev/setup.sh` does not drop the test database.** It runs `db:create`, a
  no-op when the database is already there. Deleting `.redmine` is not the same
  as starting clean.
- **A CI run marked "cancelled" is usually the concurrency group, not a failure.**
  Pushing again supersedes the run in flight. Read the *head's* run, not the
  newest completed one.
- **A failing gate in this container is worth reproducing before believing it.**
- **`rails runner` without `RAILS_ENV=test` boots development and dies on a
  missing `listen` gem.** Every command against a host needs `RAILS_ENV=test` in
  the *same* invocation — shell exports do not survive between tool calls.
- **PostgreSQL rejects `ORDER BY` on a column that `SELECT DISTINCT` does not
  select.** `Redmine`'s `rolled_up_trackers_base_scope` is `distinct.sorted`, so
  plucking two columns from it needs `reorder(nil)` first.
- **`.or` must come before `.distinct`, not after.**
- **MariaDB 10.11 rejects a table alias in a single-table `DELETE`.**
  PostgreSQL and MySQL 8.4 both accept it, so a statement can pass six of the
  nine CI cells and fail three.
- **`mariadb -e "…" | head` reports `head`'s exit status, not MariaDB's**, and
  MariaDB echoes a failing statement instead of raising visibly.
- **MariaDB *can* be installed in this container** — `apt-get install -y
  mariadb-server libmariadb-dev`, then `mariadbd --user=mysql
  --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock` in the background,
  a `redmine` user with `GRANT ALL`, and `dev/setup.sh <branch> mysql <ruby>`.
- **A unique index cannot enforce a key with a nullable column** on any of the
  three supported databases.
- **A cache built from the rules is not invalidated by the scope writer.**
  `Resolver.reset_cache!` clears both request caches, but it has to be *called*.
- **InnoDB refuses to drop the last index with a foreign key's column
  leftmost** (MySQL error 1553). Migration 005 checks for its replacement first.
- **Rendering from a Redmine `before_action` answers before `require_admin`.**
  Core's `WorkflowsController` declares its finders before the authorization
  callback, so anything a plugin renders from one of them is returned to whoever
  asked. Collect and let the action decide. `ProjectWorkflowsController` is the
  other way round on purpose — `authorize` is declared first, so *its* finder
  may render.
- **A migration's effect is invisible to the process that ran it.**
  `connection.table_exists?` still answered `true` after `drop_table` in the same
  `rails runner`, so a check written in one process proves nothing.
- **PostgreSQL will not cast a text literal to a timestamp inside a `SELECT`
  list.** The backfill uses `CURRENT_TIMESTAMP`.
- **A spec that fails while creating a project poisons the database for later
  runs.** To clear it: `DELETE FROM projects_trackers WHERE project_id NOT IN
  (SELECT id FROM projects)` — without a table alias, or MariaDB refuses.
- **A new project already has `Setting.default_projects_modules` enabled.**
  Guard with `module_enabled?`.
- **`Project#archive!` is private; `Project#archive` is not.**
- **Redmine's I18n applies only the `one`/`other` plural forms to Polish.**
- **A YAML value containing `": "` needs quoting.** `spec/locales_spec.rb` now
  catches it, on every host.
- **The Bash tool's working directory persists between calls — sometimes.**
  Prefix edits with an explicit `cd /home/user/redmine_project_workflows &&`.
- **`Rails.application.config.to_prepare` in `init.rb` never runs.** Call
  `apply_patches` in the body of `init.rb` instead.
- **A plugin's permissions accumulate on every code reload in development.**
  `Redmine::AccessControl.map` appends, and `PluginLoader` re-runs every
  `init.rb` from a `to_prepare` block. Harmless — `permission(name)` uses
  `detect` — and true of every Redmine plugin, so it is not the plugin's to fix.
- **Never let `spec/spec_helper.rb` apply the patches itself.**
- **Redmine 7.0 has no `request_store`.** Use
  `RedmineProjectWorkflows::Current`, and reset it in specs.
- **The plugin is copied into the Redmine host, not symlinked.**
- **Run the migration checks before the suite.** `maintain_test_schema` reloads
  `db/schema.rb` when the suite starts and wipes the plugin's migration
  bookkeeping, after which `VERSION=0` silently does nothing.
  `dev/check-backfill.sh` re-migrates, so a reversibility check straight after
  it is meaningful again.
- **`render_404` does not abort the action.** It renders and returns `false`. In
  a `before_action` the *chain* does halt, so one `render_404` as the last
  statement of a callback is safe; two are not.
- **`User#roles_for_project` caches memberships on the object.**
- **`inherit_mode: merge: Exclude` in `.rubocop.yml` is load-bearing.**
- **The break in Redmine core is 5.1 → 6.0, not 6.1 → 7.0.** What changed at 6.0
  is that CSS icons became SVG sprites — now five things the plugin renders: the
  multiselect toggle, the workflow summary's empty cell, an icon link, a
  collapsible fieldset's legend, and a table row-group expander. All five go
  through `RedmineProjectWorkflows::VersionHelper`. `app/helpers/workflows_helper.rb`
  and `app/views/workflows/_form.html.erb`, on the other hand, are byte-identical
  between 6.1 and 7.0 and differ from 5.1 only in how the toggle link is written.
- **A fixture-based spec can pass for the wrong reason.** `projects_002` has no
  member for `users_002`.
- **`safe_attributes=` sets `project_id` before `tracker_id`**, on purpose. This
  is why finding G03 is not a two-line fix.
- **Rails casts oddly in `where(id:)`.** `Project.where(id: ['1e5'])` returns
  project 1. Check the *shape* of an id (`/\A\d+\z/`) before querying, or —
  better, where the list is already loaded — intersect against the loaded list,
  which is what the inventory's filters and `ProjectOptions` both do.
- **A workflow rule can make an issue invalid.** A generic `due_date required`
  rule makes `Issue.create!` fail in a spec that arranges the rule first.
- **`rails-ujs` is loaded on all three versions**, so `link_to ..., method:
  :post, data: { confirm: ... }` works. Worth re-checking if a future Redmine
  drops it: the plugin's three INV-3 actions are all such links. The row and
  column actions do not depend on it — they are `link_to_function` with an
  `onclick`, and their confirmation is `window.confirm` in the plugin's own
  function.
- **The independent review ran in this context, not a fresh one.** The execution
  environment for this session forbade spawning subagents, as it did for WP3 and
  WP4, and `CLAUDE.md` asks for a fresh one "if a subagent mechanism is
  available". Treat WP3, WP4 **and WP5** as having had a weaker review pass than
  WP2, and let the next review session look at all three. The review did find
  three things this time — the relation copy above, a `%{count}` replaced only
  once, and a confirmation that said "changes" where it means "affects".

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
