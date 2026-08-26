# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0, WP1, WP2, WP3 and WP4 are **done**. WP5 is next and has
  not been started. WP0..WP7 are specified in `docs/implementation-plan.md`.
- **What exists:** the plugin as shipped in 0.0.3, the WP0 repairs, the scope
  model from WP1, the core seams from WP2, WP3's per-scope summary page and
  inventory, and — as of this session — a **Workflow tab in project settings**,
  so a project can run its own workflow without a system administrator. Two
  permissions gate it.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/docs-review-su98z4`, which the environment had prescribed; nothing was
  committed there.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** **two**, both in `docs/DECISIONS.md` under "Open — for Jan",
  both non-urgent and both continued on the safest default. (1) What should
  happen to an issue moved into a project whose workflow does not use its status
  — finding G03. (2) Whether a project may give itself its own workflow for the
  builtin *Non member* and *Anonymous* roles.
- **Open findings:** 4, unchanged in number. `claude` F06 (row and column bulk
  actions skip mixed cells, WP5), `external` F11 (the README understates the
  operational risks, WP7), G02 (a cross-project bulk tracker change is an N+1,
  WP6) and G03 — which WP4 examined and deliberately left as core behaves, with
  its `Resolution:` line now saying so and the decision recorded as open choice
  1. One more is marked wont-fix (G04).
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` lists them, plus
  one line from `TEMPLATE.md` that is not a finding.
- **`spec/characterization/`:** still **gone**, since WP3. The convention stands
  and is written down in `dev/README.md`: a defect that is found but not yet
  fixed is pinned there first.

## What this session produced

**A project can manage its own workflow.** Two permissions under the issue
tracking module — `view_project_workflow` and `manage_project_workflow` — and a
**Workflow** tab in project settings. This is the only place in the plugin where
a non-administrator writes workflow data, so it carries the heaviest
authorization coverage: anonymous, a member with neither permission, somebody
who is not a member at all, view-only reading and being refused a write,
manage-only writing, the same user on a project the permission does not cover,
an administrator, and the module switched off.

**The tab is the list; a matrix edits one combination.** One line per tracker the
project has enabled and role somebody holds in it, with the state in words
(*Own workflow*, *Own empty workflow*, *Inherits the generic workflow*), the
number of rules the project holds itself, and the actions that would change it.
Clicking the number opens that combination's matrix. The administration screens
edit a whole selection at once and need a third "no change" state in every cell
for it; one combination per matrix here keeps every cell a plain yes or no, and
bulk editing across combinations is WP5's subject anyway.

**The generic workflow is the read-only reference.** A combination the project
has not taken over renders the generic rules as **disabled checkboxes** — which
is exactly how core already draws a cell that cannot be changed, and exactly
what applies to that project until it takes over (INV-5). So you can see what
you would be copying before you copy it. Once the project has a scope the grid
is core's own `workflows/_form` partial, rendered unchanged, so the project
matrix cannot drift from the administration one.

**Saving while the project still inherits is refused.** `TransitionWriter` and
`PermissionWriter` create the scope a project write implies, so accepting such a
save would turn "save" into "enable" — on a screen that never offered an
editable grid. The three actions of INV-3 stay the only way to take a workflow
over. The response is a warning and the same screen again, and nothing is
written.

**INV-7, structurally rather than by checking.** The project is named by the path
and by nothing else; `authorize` runs before any other callback; the writers are
always called with `[@project.id]`; and the tracker and role are matched against
lists built from the project — the trackers it has enabled, the roles somebody
holds in it — rather than queried, because `Project.where(id: ['1e5'])` resolves
to project 1 and the shape of an id is therefore not something to rely on.
Anything not on those lists is a 404.

**The tab is not a Deface override**, so the override count stays **eleven**
(INV-9). It is a patch on `ProjectsHelper#project_settings_tabs`: the tab list is
data, so adding to it is an append with no anchor to go stale. Its entry names
the *controller action* it leads to rather than a permission, because two
permissions reach the screen and somebody who may manage a workflow must see the
tab without also holding the permission to view it — Redmine's `allowed_to?`
takes either shape.

**Two repairs found on the way.**

1. `spec/models/project_statuses_spec.rb` was passing on `projects_trackers`
   rows another spec file happened to leave in the database, and one of its
   assertions — that the generic status is *absent* from a project's rolled-up
   list — is only true for a project with no descendants, because a scope on a
   parent says nothing about its children (INV-6). It now declares the fixture
   and uses a leaf project. **The third spec in this project found to be passing
   for a reason it never stated.**
2. Locale parity was checked by hand at the end of every session until now. It
   is `spec/locales_spec.rb`: all eight files parse, and each carries exactly the
   keys `en.yml` carries.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 382 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 382 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 382 examples, 0 failures |
| RuboCop | 78 files, no offences |
| `zeitwerk:check` | "All is good!" on 5.1, 6.1 and 7.0 |
| Migration reversibility up → 0 → up | clean on 7.0, asserted by reading the schema back in a **separate process** after each step. WP4 changes no migration |
| Backfill (`dev/check-backfill.sh`) | passes on 7.0 + PostgreSQL |
| Locale parity | now a spec, green on all three hosts: eight files, 45 keys each |
| Independent review | run in this context rather than a fresh one — see "Known traps" |
| New specs against the old code | see below |
| CI | **run 26 is green on all nine cells plus RuboCop**, on `9559eab` — Redmine 5.1, 6.1 and 7.0 × PostgreSQL, MySQL and MariaDB. Run 27 covers the two examples added after it; check it |

**The "fails on the old code" checks, run rather than assumed.** Each was done
by putting one thing back and leaving the rest of WP4 in place:

| Reverted | Fails |
| --- | --- |
| the `project_module` block in `init.rb` (the two permissions) | 47 examples |
| `patches/projects_helper_patch.rb` (the tab entry) | 3 |
| `patches/projects_controller_patch.rb` (the tab's rows) | 7 |
| the refusal to save while the project inherits | 2 |
| `ProjectOptions.roles` widened past the project's members | 9 |

The 96 new examples cover authorization (nine cases), the tracker and role
intersection (four, including an id of the wrong shape and an unknown rule
type), both matrices read-only and editable, both saves, all three INV-3
actions, the `back_url` round trip including one pointing off the installation,
INV-6 (a scope on the parent project is not the child's), the used-statuses
filter both ways, and the rendered page — that all three transition grids are
submitted, which is the thing that would silently drop author and assignee rules
if the form ever lost them, and that the two new version-conditional icon shapes
come out right on both sides of the 5.1 → 6.0 break.

## Exact next step

Start **WP5** from `docs/implementation-plan.md`: bulk editing in the matrix. In
outline:

1. `claude` F06 — mixed-value cells get the same CSS classes and data attributes
   as ordinary checkboxes, so Redmine's own row and column toggles reach them.
   Read the finding first; it names the classes.
2. Explicit per-row and per-column actions **Yes / No / Unchanged**. Toggling is
   not the same as setting to No, and setting to No is the case that needs it.
3. The size of the selection shown above the matrix, and a confirmation once an
   action would touch more than a configured number of workflows. That threshold
   is a new plugin setting — the plugin has none today, so `init.rb` gains a
   `settings` block and `Setting.define_plugin_setting` starts applying.
4. Keyboard operation, visible focus and `aria-label`s from the start;
   "Unchanged" gets clearer wording and a legend.

WP5 touches the administration matrices, which the project matrices now share
`workflows/_form` with — so anything done to that partial's markup has to be
checked on **both** screens. `spec/controllers/project_workflows_controller_spec.rb`
has the assertion that all three grids are submitted; keep it passing.

## Known traps

Everything below cost time at least once. The first eight are new this session.

- **Redmine renders every settings tab's partial on every visit.**
  `showTab` only hides and shows what is already in the page, so a tab's content
  is built whether or not anybody clicks it. Its data therefore has to exist
  before the view does, and it has to be cheap.
- **`ProjectsController#update` calls the `settings` *method* and then renders
  the settings view.** A `before_action` would not run on that path, so the tab
  would render without its rows after a failed save. Patch the method.
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
  compound command does not reliably persist to the next tool call, and a
  `git stash pop` that lands in the host's checkout says "No stash entries
  found" while your work is still stashed in the plugin's. Use absolute paths,
  and check `git stash list` in `/home/user/redmine_project_workflows` before
  believing anything is lost.
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
  through `RedmineProjectWorkflows::VersionHelper`.
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
  drops it: the plugin's three INV-3 actions are all such links.
- **The independent review ran in this context, not a fresh one.** The execution
  environment for this session forbade spawning subagents, as it did for WP3, and
  `CLAUDE.md` asks for a fresh one "if a subagent mechanism is available". Treat
  WP3 **and WP4** as having had a weaker review pass than WP2, and let the next
  review session look at both.

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
