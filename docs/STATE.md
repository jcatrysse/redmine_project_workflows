# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

- **Work package:** WP0 through **WP8** are done and have been for two sessions.
  `docs/implementation-plan.md` runs WP0..WP8 and every row reads *done*. There
  is no WP9. What happens now is the **review loop** in `docs/review/`.
- **This session was both roles at once** — a review *and* the fix for what it
  found, because Jan asked for both in one go. The findings file is
  `docs/review/findings/2026-08-26-claude-second-review.md`, and unlike a pure
  review it went to `claude/dev` with the fixes rather than to `main` on its own:
  the reason `docs/review/README.md` sends a findings file to `main` is so that
  another session can act on it, and this session acted on it.
- **What exists:** the plugin at **0.1.1**. 0.1.0 is the scope model and the
  eight work packages; 0.1.1 is this session, which is two major fixes on the
  path "an administrator presses Save" plus nine smaller ones.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. This session started on
  `claude/redmine-workflows-plugin-review-zpjyfv`, which held the same commit as
  `claude/dev`, and checked out `claude/dev` before touching anything.
  `git checkout -B claude/dev origin/claude/dev` is the safe form.
- **`main`:** unchanged. Jan asks for the merge himself. Worth knowing before he
  does: `main` still carries the *old* CI setup — `.github/workflows/rspec-51.yml`
  and `rspec-60.yml`, two cells — while the nine-cell `specs.yml` exists only on
  `claude/dev`. The merge replaces the two with the matrix; the two names linger
  in GitHub's workflow list afterwards with no file behind them, which is
  cosmetic.
- **Open findings:** **one** — `G02`, the batching pass for a cross-project bulk
  tracker change, deferred with the reasoning recorded. `G03` had been left at
  `open — deferred` in its findings file although Jan **answered it A** the same
  day; `docs/DECISIONS.md` had the answer and the findings file did not, so the
  status is corrected to `wont-fix` and the two documents now agree. This session
  adds one `wont-fix` (`R05`, the project selector lists every project) and one
  `invalid` (`R09`, checked against core and withdrawn); everything else across
  every findings file is closed. To check:
  `grep -rn '^- \*\*Status:\*\* open' docs/review/findings/` — one hit plus a
  line in `TEMPLATE.md`, which is not a finding.
- **`spec/characterization/`:** still **gone**, since WP3.
- **Open choices:** none. Everything decided this session is Class A or a Class B
  with the safest reversible default taken and logged in `docs/DECISIONS.md`.

## What this session produced

A full independent review of `9a1a9ef`, then the fixes for all of it. Thirteen
findings; the two that matter are both on the administration matrix's Save.

### R01 — a cell left at *(No change)* was deleted anyway

One cell of the transitions matrix is **three controls** (`always`, `author`,
`assignee`) over **two stored rows**. Each of the three can independently render
as a `<select>` defaulting to core's *no change*, which the controller strips
before the writer sees it — and the writer's delete was keyed on
`(old_status_id, new_status_id)` alone. So one submitted column deleted the rows
of the other two, in every workflow of the selection, and reported success.

Reachable from the **default state of the screen**: with two workflows that
disagree about a transition, the `always` cell is a mixed dropdown while the
`author` and `assignee` cells are unchecked checkboxes with their hidden `0`.
Save without touching anything, and the transition is gone. Because the plugin
routes core's own `WorkflowTransition.replace_transitions` through this writer,
it applied to the **generic** workflow too — a change to what stock Redmine does,
confirmed by calling core's implementation through `Method#super_method` side by
side with the plugin's.

The delete is now per rule group, and the shared author/assignee row is read
before the delete so that a flag left at *no change* survives — which is what
core's row-by-row update does.

### R02 — Save turned "inherits" into "own empty workflow"

`ProjectWorkflowsController` has refused a save while inheriting since WP4 and
`docs/design.md` states the rule. The administration screens did not implement
it, and two halves made it dangerous: the grid shows the rules the selection
holds *itself*, so an inheriting project renders **empty** (measured, against a
generic workflow that had the transition), and Save then wrote that emptiness
back as an own *empty* workflow — in which no issue in the project can change
status at all. With **All** selected, for every project at once.

The writers now write only into combinations the project has already taken over
and return how many they refused; `ScopeWriter.ensure_scopes` is gone, so
creating a scope is `.enable` and nothing else. The controller warns and
withholds the success notice when nothing was written, and the panel says so
above the grid before anything is pressed.

### And the word "inherits", which Jan asked about afterwards

He read the plugin's own screens and asked what workflow inheritance was, since
Redmine has none. That is the strongest kind of wording bug report there is: the
maintainer misreading his own product. The first of the three states now says
**"Follows the generic workflow"** in all eight languages -- seven strings each.

The **internal** vocabulary is unchanged on purpose, and `docs/DECISIONS.md` says
so, so that a later session does not "fix" the difference by reverting the
strings: the state symbol is still `:inherits`, so are the locale key names,
`ScopeWriter.return_to_inheritance`, the `project-workflow-scope-state inherits`
CSS class a theme may already target, and INV-6's own wording. The words on
screen and the words in the code are allowed to differ where the code's word is
precise and the screen's word was not.

### The other eleven

`R03` core's issue-status badge reads `workflows` with no project predicate and
was missing from the design's "complete list" — documented, not changed, because
it is a badge rather than a gate. `R04` scope creation batched with `insert_all`.
`R05` the project selector lists every project — recorded as a cost, left.
`R06` `Issue#workflow_rule_by_attribute` is private again. `R07` the helper
injected into core's `issues/_attributes` is guarded with `respond_to?`.
`R08` a malformed matrix submission is rejected rather than raising. `R09`
withdrawn as invalid. `R10` the "ten anchors" sentence in `design.md`.
`R11` `locales_spec` asserts plural forms, and es/pt/pl use Redmine's own words.
`R12` the threshold field is `type=number min=0`. `R13` a matrix save is one
transaction.

### The specs that had to change, and why that is not a weakening

Nineteen existing examples arranged project rules by calling a writer and relying
on it to create the scope — an arrangement that relied on the defect. They now
give the project its own workflow first. Four asserted the old behaviour outright
(`.ensure_scopes`, and *"creates one for each tracker and role it wrote"*); those
are inverted or moved onto `.enable`. Two model specs now reach
`workflow_rule_by_attribute` with `send`, as core's own tests do, because it is
private again.

## Evidence

| Check | Result |
| --- | --- |
| Plugin suite, 5.1-stable + PostgreSQL 16 | **619 examples, 0 failures** (was 585; 34 added) |
| Plugin suite, 6.1-stable + PostgreSQL 16 | **619 examples, 0 failures** |
| Plugin suite, 7.0-stable + PostgreSQL 16 | **619 examples, 0 failures** |
| Plugin suite, 7.0-stable + **MariaDB 10.11** | **619 examples, 0 failures** |
| Fails on the old code | **19 of the new examples**, run rather than assumed: committed the fix, wrote the `9a1a9ef` version of `lib/` and the two changed partials back with `git show`, ran, then `git checkout -- .`. The rest are positive controls that must pass on both sides |
| Migration up → 0 → up | clean on all four hosts, run **before** each suite; schema checked by hand on 7.0 (no `workflows.project_id`, no `project_workflow_scopes`). This session adds no migration |
| Backfill check | `dev/check-backfill.sh` passes on the 7.0 host |
| RuboCop | 92 files, no offences, **no new `.rubocop_todo.yml` entry** |
| `zeitwerk:check` | passes on the 7.0 host (one new file, `services/matrix_scope.rb`) |
| JavaScript gate | `node dev/check-bulk-js.mjs` — all thirty-two checks |
| Locale parity | eight files, **94** keys each (was 92) |
| MySQL 8.4, and 5.1/6.1 on MySQL and MariaDB | not run **locally** — five of the nine cells; CI covers them, see the row below |
| CI | **green.** Ordinary `push` runs cover this session: run **71** on `13871c2` (all the code), run **74** on `61c1e1c` and run **75** on `732438c`, each ten jobs — nine cells (5.1 / 6.1 / 7.0 × PostgreSQL / MySQL / MariaDB) plus RuboCop, each cell through migration reversibility, the backfill check, `zeitwerk:check` and the specs. The wording commit `6ef3fc3` and this file are covered by run **77**. Several runs read "cancelled" (70, 72, 73, 76): that is the concurrency group superseding a run, not a failure — read the run for the commit you care about |

## Exact next step

1. **Nothing to check first**, beyond reading the run for the head. CI is green
   on every commit of this session that carries code.
2. **It is Jan's turn.** `docs/review/findings/2026-08-26-claude-second-review.md`
   is the readable account of what was wrong and what was done about it; the
   CHANGELOG's 0.1.1 entry is the same thing for a user.
3. The one behaviour change worth his eye is **R02**: an administrator who
   selects a project that inherits and presses Save now gets a warning and no
   change, where before the project silently took the workflow over. Reversing it
   is `writable_pairs` in the two writers.
4. If he wants more, the candidates already written down are unchanged: the
   layered SVG diagram, the issue show page, row and column actions on the
   field-permissions matrix, and finding `G02`.

## Known traps

Everything below cost time at least once. The first five are new this session;
the rest are carried forward.

- **A push here takes several minutes to produce a CI run, and this session drew
  the wrong conclusion from that.** Two pushes showed no run after ten minutes of
  polling, so `specs.yml` was dispatched by hand and STATE was written to say
  that pushing does not trigger CI. It does: runs 70 to 76 are all `push` events,
  they simply arrive late. The manual dispatch was unnecessary, and run **77**
  cancelled run **76** — the automatic run for the same commit — through the
  concurrency group. Wait longer before concluding that a mechanism is broken,
  and check the `event` field on the run rather than only its number.
- **A cell of a matrix is not the unit a delete may key on.** Three controls
  over two rows, each of which can independently be left at "no change": the key
  is (cell, rule group), and the two flags inside the shared row need finer
  handling still. Whenever a screen submits several controls under one key, ask
  which of them the delete is allowed to speak for.
- **A grid that renders what the selection *stores* lies about what applies.**
  The administration matrix shows a project's own rules, so a project that
  inherits renders as an empty grid — which reads as "nothing is permitted" and
  is the opposite of the truth. The panel above it is the only thing that can say
  so, and it has to, because the grid is the part people read.
- **`git checkout -- .` after a red-on-old-code run restores to HEAD.** Which is
  right *only if the fix is committed first*. Commit, then `git show <old>:<path>
  > <path>`, run, then `git checkout -- .`. Carried over from last session and
  used correctly this time; keeping it here because it is the trap most likely to
  destroy work.
- **PostgreSQL and MariaDB both stop when the container is idle.** `pg_isready`
  and `mariadb -e 'SELECT VERSION()'` before blaming a spec: a dead server shows
  up as `ConnectionNotEstablished` in a `before(:suite)` hook, which reads like a
  broken spec_helper.
- **`Array#sort` raises on booleans.** `pluck(:author, :assignee).sort` is
  `comparison of Array with Array failed`, because `false <=> true` is nil. Sort
  by a mapped key.
- **Proving an example red on the old code: stash the one file, not the tree.**
  `git stash push lib/…/the_one_file.rb`, run the suite, `git stash pop`. What
  makes this go wrong is stashing too much: a new locale key has to **stay** in
  the working tree, or `I18n.t` returns the "translation missing" string and the
  example fails for a reason that has nothing to do with the code under test —
  which reads as proof and is not. And once the change is **committed**,
  `git stash push` on that file has nothing to stash: it exits 0, says "No local
  changes to save", and the "old code" run is the new code passing itself. Use
  Commit the change, then use `git show <old-sha>:<path> > <path>` …
  `git checkout -- <path>` instead. This session was fooled by the stash form
  once, and then by the replacement form once — see the next entry, which is why
  "commit first" is part of the recipe rather than an aside.
- **…and `git checkout -- <path>` afterwards restores it to `HEAD`, which throws
  an *uncommitted* fix away.** The mirror image of the trap above, and it cost
  this session the C01 view fix once: writing the old version over the file,
  running, then `git checkout --` left the old version in place, because `HEAD`
  did not yet carry the new one. `git status` then shows the spec file modified
  and the fix silently gone. **Commit the fix first**, then restore from the
  previous commit — that way `git checkout --` puts the fix back rather than
  removing it.
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
