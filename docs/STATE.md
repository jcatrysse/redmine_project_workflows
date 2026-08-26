# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP6** are **done**. **WP7** (documentation,
  locales, release) and **WP8** (new this session — status help and the
  transition map on the issue form) are not started. All of them are specified
  in `docs/implementation-plan.md`, which now runs WP0..WP8.
- **What exists:** the plugin as shipped in 0.0.3, the WP0 repairs, WP1's scope
  model, WP2's core seams, WP3's per-scope summary page and inventory, WP4's
  Workflow tab in project settings, WP5's row and column actions, and — as of
  this session — **WP6: an audit trail, a project-versus-generic comparison
  screen, and a counter and undo behind the row and column actions.**
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/issue-status-info-flowchart-v701un`, which the environment had
  prescribed; nothing was committed there. Note that the local `claude/dev` was
  36 commits behind the remote at checkout — run `git pull --ff-only origin
  claude/dev` first, or you will silently work against WP4-era files.
- **`main`:** unchanged. Jan asks for the merge himself.
- **Open choices:** **one**, new this session — how WP8 should draw the
  flowchart. Options, plain-language explanations and a recommendation are in
  `docs/DECISIONS.md` under "Open — for Jan". Not urgent: WP8 is not started and
  nothing waits on the answer.
- **Open findings:** 3, unchanged in number. `external` F11 (the README
  understates the operational risks, WP7), G02 (a cross-project bulk tracker
  change is an N+1) and G03 (`Issue#project=`). **G02 was WP6's to settle and it
  now stands with WP2's reasoning confirmed rather than overturned** — see
  `docs/implementation-plan.md`. One more is marked wont-fix (G04).
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` lists them, plus one
  line from `TEMPLATE.md` that is not a finding.
- **`spec/characterization/`:** still **gone**, since WP3. The convention stands
  and is written down in `dev/README.md`: a defect that is found but not yet
  fixed is pinned there first.

## What this session produced

### The new requirement, recorded as WP8 — and core already has half of it

Jan asked for a clickable info icon on the issue form explaining every available
status, plus a Jira-style flowchart of the possible status changes. The research
changed what WP8 has to build.

**Redmine core already ships the info icon**, on 5.1, 6.1 and 7.0 alike.
`issues/_attributes.html.erb` renders an `icon-help` link beside the status
select which opens core's own `#issue_statuses_description` modal: a `<dl>` of
status name and `IssueStatus#description` (a real core column on every supported
version, edited at *Administration → Issue statuses*), where clicking a name
*applies* that status. It lists `@allowed_statuses` — which is
`Issue#new_statuses_allowed_to`, the method **this plugin replaces in full** — so
it is already describing the project's own effective workflow. It renders only
when at least one available status has a description filled in, which is why an
installation that has never used that field concludes the feature is missing.

So WP8's first half is specs (INV-4: the modal must never name a status only
another project's rules reach) and a README paragraph, not new code. **The map is
what is genuinely new**, and its load-bearing design clause is that it must not
contradict the status dropdown: `new_statuses_allowed_to` also drops closed
statuses for a blocked issue or one with open subtasks, open ones for a subtask
of a closed parent, and filters the author and assignee variants by identity.
`docs/design.md` carries the whole target under "Telling the end user what the
workflow is (WP8)".

### WP6, in three commits

**Who last changed this workflow.** The scope table has carried
`created_by_id`/`updated_by_id` since WP1 and nothing maintained them on the
ordinary edit path: `ScopeWriter.ensure_scopes`, which every project matrix save
goes through, deliberately left an existing scope alone. `touch_scopes` is the
stamp, called *before* the create so a row inserted by the same call is not
stamped twice, and the two halves stay apart on purpose — `created_*` records who
decided the project runs its own workflow, `updated_*` who last changed the
rules. The inventory and the project settings tab both show it, with the users
loaded in one query per page. The sentence is core's own `authoring` helper with
`label_updated_time_by`, so it needed **no locale key of its own** — that key is
already translated in every language Redmine ships.

**A project's workflow against the generic one.** `Services::WorkflowComparison`,
a `compare` action, a screen, and links from the settings tab, either matrix
header and the administration inventory — all three built by one helper so they
cannot drift about when the link is offered. The unit of comparison is **core's
grid, not the stored row**: `WorkflowsController#edit` partitions transitions with
`reject { author || assignee }`, `select(&:author)` and `select(&:assignee)`, so a
row with both flags set is in two grids at once, and comparing grid against grid
is what makes the answer match what the screen shows. Field permissions get a
third state transitions cannot have — both sides speak and disagree.

**A counter and an undo.** WP5's actions already changed only the screen; nothing
on the page said so, and one click could change a hundred cells with no count and
no way back short of reloading. There is now a region above the matrix with the
count, the workflow rules it costs, an Undo and the sentence that nothing is
saved until Save is pressed. The undo is a **stack**, and it restores the value
each control held *before the action* — not the value the page was opened with,
which is what "no change" already means, and which is the same thing only for the
first action. No new Deface anchor: it renders from the two partials that are
already above the matrix, so the **INV-9 count stays at thirteen in eleven
files.**

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | 483 examples, 0 failures |
| Plugin suite, 6.1-stable + PostgreSQL 16 | 483 examples, 0 failures |
| Plugin suite, 7.0-stable + PostgreSQL 16 | 483 examples, 0 failures |
| RuboCop | 82 files, no offences |
| `node dev/check-bulk-js.mjs` | **32** checks, all ok (was 16) |
| Migration reversibility up → 0 → up | clean on 7.0, run **before** the suite. WP6 changes no migration |
| Locale parity | eight files, **74** keys each (was 53) |
| Independent review | run in a **fresh subagent** — the first session where the mechanism was available. It found **seven** real defects, all fixed in the last commit; see below |
| CI | runs **36 through 39 green on all nine cells** — the WP8 docs commit and the three WP6 commits. Run **40**, for the review-fix commit at the branch head, was still in flight when this file was written — **check it first.** |
| New specs against the old code | measured, see below |

**The "fails on the old code" checks, run rather than assumed.** Each was done by
putting one file back to its state before the commit and leaving the rest in
place, against the full suite on 7.0. The working tree was **committed first**, so
the restore afterwards is exact — a scratch script that restores with
`git checkout` restores to HEAD, which destroyed three files' worth of WP5 in an
earlier session.

| Reverted | Fails |
| --- | --- |
| `services/scope_writer.rb` (the stamp) | 5 |
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
| the review fixes: `services/workflow_comparison.rb` | 8 |
| the review fixes: `services/scope_writer.rb` (the copy path's stamp) | 1 |
| the review fixes: `project_workflows_controller.rb` | 3 |
| the review fixes: `compare.html.erb` | 3 |
| the review fixes: `project_workflows_helper.rb` | 3 |

The 64 new examples cover the audit stamp on all four write paths and its absence
where a project inherits, the audit pair in the cell and its absence on an
inheriting one, a query-count proof that the audit users load in one query
however many rows a page holds, the comparison's four states and both orderings,
`compare`'s authorization (anonymous, neither permission, view-only, and the same
user in a project the permission was not given for), its two 404s, all three
entry points to it, and the counter and undo present on the two transition
matrices and absent from the two field-permission ones and from a read-only
project matrix. The last nine came out of the review: two rows for the same
(status, field) that disagree, the row counts, the copy path's stamp, the
unreachable-field footnote, and the 403 a disabled issue tracking module gives.

### What the independent review caught

Worth reading before the next one, because the pattern repeats. Seven of its
thirteen findings were real, and the most important was **latent, not red**: the
field-permissions comparison built its map with `to_h` over an unordered `pluck`,
so two rows for the same (status, field) that disagree made the page depend on
which row the database returned last — the same installation comparing
differently on PostgreSQL and on MySQL, with nine green CI cells hiding it. Each
side now carries the whole sorted list and the page shows both, which is what core
does too. The others: the copy screen never stamped the audit columns; the compare
page counted distinct keys where the settings tab counts rows; two `COUNT(*)`
queries were redundant; a difference can name a field no project screen can
change and nothing said so; the 403/404 documentation was wrong in three places;
and two new specs passed for the wrong reason. One finding was declined with a
reason (the parenthetical plural, because the sentence carries two numbers and one
interpolation cannot pluralise both).

## Exact next step

**Check CI run 40** (the branch head) before anything else — it was in flight
when this file was written; 36 through 39 are green. A run reading "cancelled" is the concurrency group
superseding it after the next push, not a failure; read the *head's* run.

Then either:

- **WP7** — documentation, locales, release. It is the last package in the plan
  and it should be last: it needs every string to exist. Finding **F11** (the
  README understates the operational risks) is scheduled into it. WP8's own
  README paragraph about *Administration → Issue statuses → Description* belongs
  here too if WP8 lands first.
- **WP8** — the status help and the transition map. Independent of WP6 and WP7
  and buildable before either. **Read the open choice in `docs/DECISIONS.md`
  first**; the recommendation is "C first, then A on top of it", and C alone is a
  useful commit.

`docs/implementation-plan.md` says WP8 is numbered last because it arrived last,
not because it depends on WP7.

## Known traps

Everything below cost time at least once. The first nine are new this session.

- **A new controller action is 403 for everybody until `init.rb` names it in a
  permission.** Administrators included, and the symptom is a forbidden page
  rather than an "unmapped action" error anywhere. `spec/plugin_conventions_spec.rb`
  now asserts structurally that every action of `ProjectWorkflowsController` is
  named by at least one of the two permissions, so the next one cannot repeat it.
- **`to_h` over an unordered `pluck` is a cross-database divergence waiting to
  happen.** Where two rows can share a key, the last one wins — and which one
  that is differs between PostgreSQL and MySQL. Nine green CI cells hide it until
  a database in the field has such a pair. Keep both, or sort before picking.
- **An unscoped `include(user.name)` on a settings page proves nothing.** Core
  renders the Members tab into the same response, so the name is there whatever
  the thing under test says. Scope the assertion with `css_select`.
- **A project whose module is disabled, or which is archived, gives 403 — not
  404.** `authorize` → `Project#allows_to?` → `deny_access` → `render_403`. Only
  a finder that cannot match its parameter gives 404. Guessing this wrong put a
  wrong table into `docs/design.md`.
- **`Set#flatten` flattens nested Sets, not the Arrays inside one.**
  `Set[[1, 2]].flatten` is still a Set of one Array, so a `reject(&:zero?)` after
  it raises `NoMethodError` on `Array`. Take the pairs out of the Set first.
- **A query-count example can measure lazy fixture loading.** A memoised
  `let(:trackers_list) { [trackers(:x), trackers(:y)] }` referenced for the first
  time *inside* the counted block adds two SELECTs to the first iteration and
  none to the second — which looks exactly like an N+1 and is not. Force the
  lists before counting.
- **A JavaScript scenario inherits the previous one's state.** The undo stack
  lives for the life of a page, so `dev/check-bulk-js.mjs` re-evaluates the whole
  `javascript_tag` block per scenario. The first version of those checks passed
  vacuously on a stack an earlier scenario had left behind, and five checks then
  "failed" for the same reason.
- **`docs/design.md` said the settings tab costs four collection queries; it is
  six.** Measured with `rails runner` and a `sql.active_record` subscriber. The
  constant-cost property was right and the count was not — so prefer stating the
  property and measuring the number rather than estimating it.
- **Redmine core already has an issue-form status help icon and modal.** Do not
  build a second one. `issues/_attributes.html.erb`,
  `label_open_issue_statuses_description`,
  `showModal('issue_statuses_description')`, and
  `issues/_issue_status_description` — byte-identical in 5.1, 6.1 and 7.0 apart
  from `sprite_icon` arriving at 6.0.
- **`git checkout -- .` in a scratch script destroys uncommitted work.** It
  restores to **HEAD**, not to what you had. **Commit first, then run revert
  experiments** against the commit, and never let such a script touch anything
  but the file it reverted.
- **Deface renames an attribute whose value contains ERB.**
  `style="width:<%= ... %>"` is matched as `td[data-erb-style]`, not `td[style]`.
  A selector that does not match produces no error and no output.
- **A `<select>` that acts on its own `change` event is an accessibility trap.**
  Arrow keys on a closed select fire `change` per step, so a keyboard user
  applies every value on the way to the one they wanted. This is why the row and
  column actions, and the undo, are links.
- **Redmine's administration screens are behind sudo mode, in the suite too.**
  A spec that logs in as administrator gets the password form instead of the page
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
  answers for Redmine's checkout rather than the plugin's. Prefix with an
  explicit `cd /home/user/redmine_project_workflows &&`.
- **Redmine's stylesheet removes the focus outline only on form controls and on
  `button.tab-left`/`button.tab-right`** — never on `a`, on 5.1, 6.1 or 7.0.
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
  `project_statuses_spec.rb` needs `:projects_trackers`. Before believing a green
  suite, ask which file loaded the fixture you are relying on.
- **A reused test database hides a missing fixture.** Two hosts disagreeing is a
  signal, not a flake.
- **Rails' `include_all_helpers` does not reach a plugin's `app/helpers`.** Name
  it with `helper MyHelper`; for a view rendered by a *core* controller, do it
  from the patch's `self.prepended(base)`.
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
  --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock` in the background,
  a `redmine` user with `GRANT ALL`, and `dev/setup.sh <branch> mysql <ruby>`.
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
  `@other ||= ...`.**
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
