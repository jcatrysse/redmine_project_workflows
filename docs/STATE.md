# STATE — where we are

> This file is the project's memory between sessions. It is rewritten in full
> at the end of **every** session (overwritten, not appended). Write it as if
> the next session knows nothing, because it does.

## Current position

> **Two sessions ran in parallel on 2026-08-28 and both pushed to
> `claude/dev`.** A planning session wrote the hardening track (WP10..WP16, two
> ADRs, the audit findings) as `c67cc0f`; a fixing session answered the
> whole-stack compatibility findings and landed the **first two items of WP10**
> on top of it. This file is the second one's rewrite and describes both.

- **The plugin is feature-complete and is in a hardening track.**
  `docs/implementation-plan.md` runs WP0..WP9 and every row reads *done*. Three
  reviews landed on 2026-08-28, and between them they turned "what is left to
  build" into "what is left to make releasable". That is **WP10..WP16** in the
  same file, carried by two new ADRs.
- **WP10 is started, not finished.** Its two items from the whole-stack run are
  **done and verified on a real 45-plugin host**; its other two — the
  unprefixed-globals convention spec, and four small confirmed defects from
  `2026-08-28-claude-audit.md` — are **not started**. See *Exact next step*.
- **The blocker is gone.** `redmine_custom_workflows`, which Jan runs, registers
  a permission called `manage_project_workflow` — the same name this plugin
  used, with an empty action list — and it loads first because plugins load
  alphabetically; `AccessControl.permission(name)` returns the first match, so
  **every write action of this plugin answered 403, administrators included**.
  The pair is now **`view_project_workflow_rules`** and
  **`manage_project_workflow_rules`** (Jan answered **B**: rename both), with a
  reversible migration over the serialized `roles.permissions` array. Measured
  on the running 45-plugin host: the request that answered **403** in the
  morning answers **302** and writes its rows. **Do not shorten either name
  back** — `init.rb`, `docs/design.md` and `CLAUDE.md`'s forbidden-constructs
  table all say why.
- **The version probe is gone too** (WP10's third item, the compat run's F02).
  `project_workflows_svg_icons?` asked `respond_to?(:sprite_icon)`, which two
  neighbours define on Redmine 5.1; it now asks `Redmine::VERSION::MAJOR`. This
  is the **interim constant** WP10 says is correct here — **WP11 absorbs it into
  ADR-002's manifest**, and `VersionHelper.core_sprite_icons?` is the one place
  it has to move from.
- **The plugin runs green beside all 44 of Jan's other plugins.** Its suite is
  **873 examples, 0 failures** on the 45-plugin Redmine 5.1 host — it was **69
  failures** that morning — and 873 / 0 on clean 5.1, 6.1 and 7.0.
- **Nothing has been released.** The plugin is at 0.1.6, unreleased; `main`
  carries 0.0.3 and there is no tag. Nothing runs in production anywhere, which
  is why Jan asked for the architectural work to be done **now** — the two ADRs
  are both large diffs that become impossible once there are installations to
  migrate.
- **Branch:** `claude/dev`, pinned in `CLAUDE.md`. Both sessions had to
  `git checkout -B claude/dev origin/claude/dev`; the second rebased onto the
  first rather than forcing, which is why the history is linear.
- **`main`:** untouched, as always.

## What this session produced

**Two sessions, two commits.** `c67cc0f` is the planning session's five
documents; the commit on top of it is the fixing session's WP10 down-payment.

### The fixing session — WP10 items 1 and 3

**A project's own workflow can be saved on a Redmine that also runs
`redmine_custom_workflows`.** Until this commit it could be *read* there and
nothing more: the settings tab rendered, every button on it was dead, and the
answer to each was "You are not authorized to access this page" — to
administrators as well. Measured on the running 45-plugin host, the same request
before and after:

| | before | after |
| --- | --- | --- |
| `POST /projects/beta/workflow/scope` as admin | **403** | **302**, the redirect after a successful write |
| scope rows written | 0 | 1 |
| project-scoped workflow rows copied | 0 | 30 |
| role-form checkboxes sharing one HTML id | 2 | none |
| `/workflows`: `icon-not-ok` / `decoration-red` on 5.1 | 0 / 3 | **3 / 0**, which is what stock 5.1 draws |

**Migration 006 carries existing grants across and refuses to guess where it
cannot know.** A role holding `:manage_project_workflow` may hold it for the
*neighbour*, and nothing in the stored symbol says which. Renaming it would take
their permission away; adding ours beside it would widen what the role may do,
which is the one direction a migration must never move on its own. So it asks
whether anything else still registers the legacy name — not "is
`redmine_custom_workflows` installed", but `AccessControl.permissions.any?`,
which is the question that actually decides ambiguity — and where the answer is
yes it leaves the grant alone and prints what to grant instead. The unambiguous
name still moves. Observed doing exactly that on the real host:

```
-- another plugin still registers manage_project_workflow; leaving role grants
   of it alone. Grant manage_project_workflow_rules to the roles that should have it.
```

**One thing a finding asked for that turned out to be impossible.** The compat
run's F04 suggested the specs work out *by reflection* which permissions the
host's plugins demand before core's issue pages render.
`redmine_view_issue_description` declares its permission with an **empty** action
hash and puts the gate in a `prepend` on `IssuesController`, so `AccessControl`
holds nothing connecting it to `issues#show` — there is nothing to reflect on.
The finding is marked `adjusted` rather than `fixed` and its resolution says so;
what was built is a **named** list of one, guarded on the permission being
registered, and therefore a no-op on the host CI runs.

**Every finding of `2026-08-28-claude-plugin-compat-5.1.md` is now closed** —
five `fixed`, one `adjusted`, four `wont-fix` (defects in *other* repositories,
recorded with their evidence and a reason). The audit's eleven remain `open`.

`CLAUDE.md`'s forbidden-constructs table gained **two rows**: a `respond_to?`
feature probe used as a version test, and a permission name a neighbour may
already hold.

### The planning session — five documents and no code

- **`docs/review/findings/2026-08-28-claude-audit.md`** — eleven findings, all
  `open`: 0 blocker, 2 major, 5 minor, 4 nit. Every one was executed rather than
  argued; four were reproduced on a running host.
- **`docs/adr/ADR-002-compatibility-as-an-object.md`** — one manifest owns every
  version fact; no feature probing; **three** compatibility states instead of
  two; warn, never refuse; CI fails where runtime warns.
- **`docs/adr/ADR-003-owned-administration-screens.md`** — the project dimension
  moves to screens the plugin owns. Deface overrides 15 → 2, the workflow
  controller patch 468 lines → under 60, core helper prepends 1 → 0.
- **`docs/implementation-plan.md`** — WP10..WP16, with the sequencing reasoning
  and a second definition of done that describes a release rather than a feature.
- **`docs/DECISIONS.md`** — Jan's fourth and fifth answers of the day, and five
  autonomous decisions including the two large rewrites that were **rejected**.

### The three reviews, and why none of them is redundant

They found disjoint sets, which is the argument for having run all three.

| Run | Method | What only it found |
| --- | --- | --- |
| `2026-08-28-claude-plugin-compat-5.1.md` | 45 plugins on one Redmine 5.1 host | the permission-name blocker (F01); `respond_to?(:sprite_icon)` answered by neighbours (F02) |
| `2026-08-28-claude-audit.md` (this session) | one plugin, executed end to end | the `WorkflowsHelper` prepend reproduced (F01); the SQLite migration abort (F02); issue-status deletion emptying a project scope (F03) |
| ChatGPT, commissioned by Jan | read-only, suite not run | the version-policy gap stated sharply; mixed valid/invalid role ids (folded in as audit F05, with credit) |

Two of ChatGPT's headline claims were **not** carried over, and the reason is in
`docs/DECISIONS.md`: *Security: MEDIUM* is supported by none of its own
findings, and *Test confidence: MEDIUM* was reached without running the suite,
which its own verification section says.

### The thing worth remembering from the drift question

Jan asked whether there is a way to tell if a new Redmine minor actually
*changed* anything, "because then it is safe". There is, and the machinery was
already here. `Services::CoreMethodDigest` was written for the test suite but
does not need one:

```
available?=true
digests computed at runtime: 19 in 34.5 ms
```

measured through `rails runner` on a live 5.1 host. That is what turned a binary
warn-or-block question into ADR-002's three states, and it is why a *verified*
host pays nothing: the digests are computed lazily, only when the running minor
is unknown.

## Evidence

Everything below was executed in this container, not quoted from the repository.

| Gate | Result |
| --- | --- |
| Plugin suite, Redmine 5.1-stable, SQLite, Ruby 3.2.6 | **861 examples, 0 failures, 9 pending** (the nine are the row-lock examples, which skip themselves on an adapter without `SELECT … FOR UPDATE`) |
| RuboCop through `.github/lint/Gemfile` | **120 files, no offences** |
| `node dev/check-bulk-js.mjs` | all checks pass |
| CI run **137** on `e7f1e90` | **11/11 jobs success** — the 3 × 3 matrix, lint and the JavaScript gate, each cell also running migration reversibility and Zeitwerk |
| Core sources checked against | Redmine 5.1-stable and 7.0-stable, fetched during the run |

Four findings were reproduced live: the `WorkflowsHelper` alias-chain
`NoMethodError`, the SQLite `no such column: TIMESTAMP` migration abort, the
issue-status deletion that takes a member's status list from two entries to
none, and the two writers raising `TypeError` on a malformed payload. One was
measured: a five-project matrix save writes 1,620 rows in 48 statements.

### The fixing session's gates (WP10 items 1 and 3)

| Gate | Result |
| --- | --- |
| Plugin suite, **5.1-stable + PostgreSQL 16** | **873 examples, 0 failures** |
| Plugin suite, **6.1-stable + PostgreSQL 16** | **873 examples, 0 failures** |
| Plugin suite, **7.0-stable + PostgreSQL 16** | **873 examples, 0 failures** |
| Plugin suite, **5.1 + PostgreSQL, all 45 plugins installed** | **873 examples, 0 failures** — the same host had **69 failures** before these changes |
| Live on the 45-plugin production host | the 403 → 302 table above, `/workflows` drawing 5.1's own empty marker, **27 settings tabs from 15 plugins** still rendering, no duplicate checkbox ids |
| Red on the old code | **measured.** F02: with the old predicate restored, **5.1** fails *is not fooled by a neighbouring plugin defining sprite_icon* and **7.0** fails *is not fooled by a context that has no sprite_icon at all*; the construct grep fails on both — four runs, executed and read. Migration: replacing `claimed_elsewhere?` with `false` turns its ambiguity example red. F01 itself: the 53 failures that disappeared on the 45-plugin host. **Stated plainly** — the new *owns every permission name it registers* example **cannot fail on this plugin's own CI**, and its own comment says so |
| Migrations up → 0 → up | **clean on 5.1, 6.1 and 7.0**, each with the database rebuilt from CORE migrations first and run BEFORE the suite: leftover columns `[]`, plugin tables `[]`, plugin `schema_migrations` rows `[]` |
| `dev/check-backfill.sh` | **OK on 5.1, 6.1 and 7.0** |
| RuboCop | **122 files, no offences**, no `.rubocop.yml` change. The one real offence (`Naming/PredicateMethod` on a mutator returning a boolean) was fixed by splitting `holds?` out of `rename_on`, not excluded |
| `zeitwerk:check` on 7.0 | **"All is good!"** |
| JavaScript gate | **34 checks pass** |
| Locale files | **eight, exact parity.** The two permission **keys** moved and the **label text did not**, so no unreviewed locale gained a string |
| INV-9 | **untouched** — fifteen overrides in twelve files, all matching on the 45-plugin host |
| CI | **not read for the fixing commit.** Four of nine cells were run locally; **the five MySQL and MariaDB cells have not been run anywhere** |

## Exact next step

**Read CI for the head, then finish WP10.** Its four items, with the two that
are done struck through:

1. ~~Rename the permission pair to `view_project_workflow_rules` /
   `manage_project_workflow_rules`, with a reversible migration over the
   serialized `roles.permissions` array.~~ **Done.** Jan answered **B**
   explicitly. Verified on a host with `redmine_custom_workflows` installed.
2. **Add the convention spec that fails when a new unprefixed global is
   registered** — permission names were the only unprefixed globals in the
   plugin. **Not started.** What exists is narrower and was written for the
   blocker itself: `plugin_conventions_spec.rb` asserts that the registration
   `AccessControl.permission(name)` answers with is *this plugin's*, for each
   name it registers. That catches a collision; it does not catch an unprefixed
   name being added in the first place.
3. ~~Replace `respond_to?(:sprite_icon)` with a version comparison.~~ **Done**,
   as `VersionHelper.core_sprite_icons?` — the interim constant WP10 calls for,
   and the single place WP11 has to move into ADR-002's manifest. The two spec
   files that restated the same expression now call that predicate instead of
   spelling it out, so a neighbour cannot make code and test wrong in the same
   direction.
4. **The four small confirmed defects from `2026-08-28-claude-audit.md`: F01**
   (`WorkflowsHelper` onto the controller helper chain — a stopgap WP12
   deletes), **F02** (three `TIMESTAMP` literals), **F04** (`is_a?(Hash)` in both
   writers), **F05** (mixed role ids answer 404). **Not started**, and F01 there
   is the same shape as the compat run's F03: a core helper a neighbour
   alias-chains. All eleven audit findings are still `open`.

   One measurement worth having before that work, taken on the 45-plugin host
   and **not** written into the audit's F01 because this session did not act on
   it: **none of Jan's 44 other plugins touches `WorkflowsHelper` today.** The
   chain there is the plugin's prepend straight onto core, for all three
   methods. So audit F01 is a **latent** risk on his current set rather than a
   live break — which is the difference between the two helpers, since
   `ProjectsHelper` has six neighbours alias-chaining it. It is still worth
   fixing, and it is still the forbidden construct; it is not on fire.

Each with a test that is red on the old code, and the commit message says how
that was known.

Before starting, read CI — nothing in the fixing commit writes SQL text, so the
MySQL family is unlikely to differ, but five of the nine cells have not been run
anywhere:

```
mcp__github__actions_list  list_workflow_runs  jcatrysse/redmine_project_workflows  branch: claude/dev
```

## Open choices

Nothing is blocking. Three things are worth Jan's eye when he next reads:

- **The permission rename shipped, and one case needs a hand.** Roles that held
  the old names are migrated automatically — **except** where another plugin
  still registers the legacy name, which on Jan's stack is
  `manage_project_workflow`. There the migration cannot tell his grant from
  `redmine_custom_workflows`' and deliberately leaves it alone: **grant
  *Manage the project's workflow* to the roles that should manage a project's
  own workflow.** Nothing that worked stops working — on that stack the
  permission has never worked. The label on the role form is unchanged.
- **Does the installation carry `redmine_base_deface`?** (compat run F09.) It is
  a hard dependency of `redmine_datetime_custom_field`, it is not in the
  repository, and the compatibility host stood in a 13-line shim. If it is not
  installed, `redmine_datetime_custom_field` cannot be loading either, because
  that dependency aborts the boot.
- **A second administration entry point** arrives with WP12. Administration will
  have Redmine's own *Workflow* and the plugin's *Project workflows*, cross-linked.
  That is ADR-003's stated price; if Jan would rather keep one entry point, the
  ADR is the place to say so and the alternative it rejects is written down.

## Rebuilding the 45-plugin host (this session's, not the ordinary one)

The ordinary single-plugin hosts are in the next section and are what almost
every session wants. This recipe is only for repeating the compatibility run.

```bash
apt-get update -qq && apt-get install -y rsync libpq-dev
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB SUPERUSER PASSWORD 'redmine';\""
su postgres -c "psql -c 'CREATE DATABASE redmine_stack OWNER redmine;'"

git clone --depth 1 -b 5.1-stable https://github.com/redmine/redmine.git .redmine/5.1-stable-postgresql

# every plugin repository, cloned to a staging directory, then copied into
# plugins/<plugin id> -- the DIRECTORY NAME MUST BE THE ID from
# Redmine::Plugin.register, which differs from the repository name for
# redmine_tags (-> redmineup_tags), redmine_plugin_computed_custom_field
# (-> computed_custom_field) and bless-this-redmine-sso.
# Private repositories need `add_repo` before the clone will authenticate.

# three plugins need a non-default branch on 5.1 (F08), and two need an edit
# before the host will boot at all (F05, F06). The findings file lists all five.

RAILS_ENV=production bundle install
RAILS_ENV=production bundle exec rake generate_secret_token db:migrate redmine:plugins:migrate
```

Traps met while doing it, all of them costing time:

- **`pkill -f "rails server"` does not kill the server.** The process is
  `puma`, and the pattern misses it — so an edit "took effect" against a server
  still running the old code, and the first run of the F03 experiment reported
  a **false negative** (200 instead of 500). `pkill -f puma`, then verify with
  `ps aux | grep [p]uma`.
- **A backgrounded `rails server` started from a tool call gets killed with the
  call.** Write a one-line launcher script and start it with
  `(setsid nohup ./start_server.sh > log 2>&1 < /dev/null &)`.
- **`rspec` disappears from the bundle when plugins are removed.** RSpec comes
  from a *neighbouring plugin's* `Gemfile` on this host, so moving plugins aside
  to get a baseline breaks the suite runner itself. Put the `group :test` block
  in the host's `Gemfile.local` (what `dev/setup.sh` does) before bisecting.
- **Bisect by renaming `init.rb` to `init.rb.off`, not by moving directories.**
  Moving a directory changes the resolved bundle; renaming `init.rb` leaves
  `Gemfile`s in place, so no `bundle install` is needed between runs. Note that
  failure counts are **not monotone** — disabling a plugin others depend on adds
  failures — so bisect one failing example, not the whole suite.
- **Redmine 5.1 has no `assets:precompile`.** It serves static files from
  `public/`. `rake assets:precompile` aborts with *"Don't know how to build
  task"*, which reads like a broken host and is not.
- **Plugin `app/overrides` directories break Zeitwerk eager loading**, because
  Redmine puts every plugin's `app/*` on the eager-load path and deface's own
  railtie only excludes railties' copies, not plugins'. That is what
  `redmine_base_deface` exists to do.

## Development environment (rebuild from scratch in a fresh session)

```bash
# packages the container does not have
apt-get update -qq && apt-get install -y rsync libpq-dev

# database
pg_ctlcluster 16 main start
su postgres -c "psql -c \"CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';\""

# a Redmine host with the plugin in it (about two minutes each; run them in the
# background in parallel). Two are enough for ordinary work.
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/setup.sh 7.0-stable postgresql 3.3.6
dev/setup.sh 6.1-stable postgresql 3.3.6

# A MySQL-family cell, worth the four minutes whenever a change touches SQL
# text -- six of the nine CI cells are MySQL or MariaDB and no PostgreSQL host
# can see what they see. This session's raw INSERT ... SELECT is exactly that
# case, and it was run here before the commit.
apt-get install -y mariadb-server libmariadb-dev
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld
nohup mariadbd --user=mysql --datadir=/var/lib/mysql \
  --socket=/run/mysqld/mysqld.sock > /tmp/mariadbd.log 2>&1 &
sleep 12 && mariadb --socket=/run/mysqld/mysqld.sock -e "SELECT VERSION()"
mariadb --socket=/run/mysqld/mysqld.sock -e "
  CREATE USER IF NOT EXISTS 'redmine'@'%' IDENTIFIED BY 'redmine';
  CREATE USER IF NOT EXISTS 'redmine'@'localhost' IDENTIFIED BY 'redmine';
  GRANT ALL ON *.* TO 'redmine'@'%'; GRANT ALL ON *.* TO 'redmine'@'localhost';
  FLUSH PRIVILEGES;"
dev/setup.sh 7.0-stable mysql 3.3.6
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-mysql

# the migration gates, BEFORE the suite, per host. RAILS_ENV=test has to be in
# the same invocation. If the suite has already run on that host, the database
# has to be rebuilt from CORE migrations first, or this proves nothing:
#   rm -f db/schema.rb && RAILS_ENV=test bundle exec rake db:drop db:create db:migrate
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows)
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test bundle exec rake \
  redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0)
# leftovers must be [] AND schema_migrations must hold no '%-%' rows
dev/check-backfill.sh .redmine/7.0-stable-postgresql 3.3.6

# sync the working tree and run the suite
RUBY_VERSION=3.3.6 dev/run.sh .redmine/7.0-stable-postgresql
RUBY_VERSION=3.2.6 dev/run.sh .redmine/5.1-stable-postgresql

# one spec file only (dev/run.sh always runs the whole directory). NOTE the
# working directory persists between tool calls -- use absolute paths or the
# next command runs inside the host checkout.
dev/sync.sh .redmine/7.0-stable-postgresql
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rspec \
  plugins/redmine_project_workflows/spec/models/project_workflow_copy_spec.rb)

# what the screen does on Redmine's OWN default data, which the fixtures are not.
# This is how F03 was measured, before and after. The test database already holds
# fixture rows, so the loader refuses until they are cleared -- inside a
# transaction that is then rolled back, so the database is left as it was.
# `include Redmine::I18n` is load-bearing: without it `l()` is missing and the
# backtrace points at Thor.
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rails runner '
  include Redmine::I18n
  include ProjectWorkflowGraphsHelper
  def project_workflow_status_label(status, id) = status ? status.name : "New issue"
  ActiveRecord::Base.transaction do
    [WorkflowRule, Issue, Tracker, IssueStatus, Enumeration, Role, Member].each(&:delete_all)
    ActiveRecord::Base.connection.execute("DELETE FROM projects_trackers")
    ActiveRecord::Base.connection.execute("DELETE FROM member_roles")
    ProjectWorkflowScope.delete_all
    Redmine::DefaultData::Loader.load("en")
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
    # ... build a project, run WorkflowGraphQuery.new(project:, tracker:, role_ids:) ...
    raise ActiveRecord::Rollback
  end')

# the JavaScript gate (also a CI job)
node dev/check-bulk-js.mjs

# eager-load check, worth running whenever a directory is added under lib/
(cd .redmine/7.0-stable-postgresql && RAILS_ENV=test RBENV_VERSION=3.3.6 \
  PATH="/opt/rbenv/shims:$PATH" bundle exec rake zeitwerk:check)

# lint (rubocop's binaries are not on PATH by default in this container)
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle install
PATH="/opt/rbenv/versions/3.3.6/bin:$PATH" \
  BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

Ruby per version: 5.1 → 3.2, 6.1 and 7.0 → 3.3. `dev/README.md` has the
prerequisites and the MySQL variant.

## Known traps

Everything below cost time at least once. **This session's traps are in
*Rebuilding the 45-plugin host* above**, because they are all about standing up
a multi-plugin Redmine; everything in this section is carried forward from
earlier sessions. Three general ones did come out of this run and belong here:

- **A feature test on a method name is not a version test, and a neighbouring
  plugin can make it lie.** `respond_to?(:sprite_icon)` is this plugin's answer
  to "does the host draw SVG icons?", and on Redmine 5.1 both the `redmineup`
  gem and `redmine_ai_triage` define that method as a back-compatibility shim.
  The plugin then takes the Redmine 6 branch on a Redmine 5 host. When the
  question is really "which Redmine is this?", ask
  `Redmine::VERSION::MAJOR` — which is what `redmine_ai_triage` does, three
  files away in the same host. This is F02.
- **Two plugins can claim the same permission name, and the loser is silent.**
  `Redmine::AccessControl` keeps a flat array and `permission(name)` returns the
  **first** match; plugins load in alphabetical directory order. The plugin that
  loses does not warn, does not raise, and does not appear anywhere in a log —
  its screens simply answer 403, administrators included, because
  `Project#allows_to?` is consulted *before* `User#allowed_to?` reaches its
  `return true if admin?`. The only visible trace is a duplicated checkbox with
  a duplicated HTML id on the role form. This is F01, and it is why the fix has
  to carry a spec asserting the registration *won*.
- **A spec that restates the production code's condition can be wrong in the
  same direction as the code, and then it agrees with itself.**
  `core_renders_sprites?` in two spec files is the same
  `respond_to?(:sprite_icon)` expression the helper uses. When a neighbour made
  it answer wrongly the specs did fail — but only because the *rendering* also
  changed; had both sides been wrong in the same way the suite would have stayed
  green over broken output. Ask the production helper, or ask a fact.

The rest is carried forward.

- **A cost asserted from memory can kill a good idea.** The first answer to F01
  ruled out a checkbox on core's copy form because it would mean a sixteenth
  Deface override (INV-9). It would not: `app/views/projects/copy.html.erb`
  renders `call_hook :view_projects_copy_only_items, project:, f:` inside that
  fieldset on 5.1, 6.1 and 7.0. The plugin reaches most of Redmine's screens
  through Deface, so "another screen, therefore another anchor" felt like
  knowledge; it was a generalisation, and the view was never opened. **Before
  costing a change to a core screen, read that screen's ERB and grep it for
  `call_hook`** — core has dozens of them and they cost nothing.
- **`Redmine::Hook::Listener` is not in `lib/redmine/hook.rb`.** That file holds
  the registry and the `call_hook` helper only; `Listener` and `ViewListener`
  are `lib/redmine/hook/listener.rb` and `lib/redmine/hook/view_listener.rb`.
  Reading hook.rb alone suggests the base class is gone. `Listener` includes
  `Singleton` and registers on `inherited`, and `add_listener` **raises** for a
  class that does not include it, so subclassing is the only supported route.
- **A view hook wants `ViewListener.render_on`, not a string built in Ruby.**
  `render_on` renders a partial through `context[:hook_caller]` — the view — so
  the partial has `l`, `check_box_tag` and the hook's context as locals, and the
  plugin writes no HTML in Ruby. The context's `project` on the copy form is the
  **source** project, because core passes `project: @source_project` explicitly
  over `call_hook`'s default `@project`.
- **Adding any method that shadows a core method moves the core-drift gate to
  red, delegates included.** `Project#copy` calls `super` and does nothing else
  of substance, and the digest table still gained an entry per minor — correctly,
  because the gate reports "the copies **and** the delegates". Measure the digest
  on each host (`CoreMethodDigest.digests["Project#copy"]` in a `rails runner`)
  and add all three in the same commit; `dev/sync.sh` the host first or the
  runner reads the previous copy of the plugin and prints nil.
- **A window of lines is not a statement, and a grep that uses one can clear the
  very shape it exists to reject.** The first version of
  `plugin_conventions_spec.rb`'s INV-4 example asked whether `project_id`
  appeared within three lines of a `WorkflowPermission.where(...)`. It passed
  against the old `base_scope` shape — because the *next statement*, three lines
  down, adds the project_id to a copy of that relation. A relation and the
  statement that narrows it are two different things, and only the second one
  runs. Grow the match until its parentheses balance and ask about that. The
  first version was written, run against the reverted code, and seen to pass;
  that is the only reason it was caught.
- **An "answers the same as" assertion can pass because both sides are wrong the
  same way.** The example comparing a copied project's effective status list
  against the source's passed with the copy disabled, because the project's own
  rule named the same two statuses the generic workflow did — so an inheriting
  copy answered the same list. Give the overriding side a status the generic
  workflow never mentions, or the assertion is a tautology.
- **A `rails runner` probe of the graph needs `include Redmine::I18n`** before
  `include ProjectWorkflowGraphsHelper`, or `l()` is missing and the backtrace
  points at Thor rather than at the line. And `WorkflowGraphQuery.new` takes
  `role_ids:`, not `roles:` — the recipe further down this file had it wrong.
- **The fresh-container `claude/dev` trap below is real and it fired again this
  session.** Worth adding to it: `git checkout claude/dev` *before* resetting
  puts the unrelated history on disk, so every documentation file reverts to a
  months-old version at once and the editor shows a state that looks like
  somebody undid the project. Nothing is lost; `git checkout -B claude/dev
  origin/claude/dev` is the whole rescue. Tagging the stale head first
  (`git tag stale-local-claude-dev <sha>`) costs nothing and makes the reset
  obviously safe.

- **A screen that models "what the rules say" is not modelling "what Redmine
  does".** Core's fallbacks live *outside* the rule tables:
  `Issue#new_statuses_allowed_to` queries the workflow and then appends the
  tracker's default status when the answer came back empty. Reading the query
  core makes is not the same as reading the method that makes it, and the whole
  of finding F01 is the difference between the two. Read core's method to its
  last line before deciding what a table means.
- **Redmine's fixtures are not Redmine's shipped configuration**, and the
  difference is exactly where two of this round's findings lived. The test
  fixtures carry no workflow at all and every spec writes its own, usually
  including an entry rule; `redmine:load_default_data` writes 48 rules per
  tracker, **no** entry rule, and a *complete* graph. A screen that is only ever
  seen against fixtures is a screen nobody has seen. The probe is four lines and
  is in *Development environment* below: clear the tables inside a transaction,
  `Redmine::DefaultData::Loader.load("en")`, measure, `raise
  ActiveRecord::Rollback`.
- **"Red on the old code" needs the *right* break.** Reverting a whole file makes
  new examples fail with `NoMethodError`, which proves the API changed rather
  than that the behaviour did. The evidence worth writing down comes from
  breaking the **one branch that decides the behaviour** and leaving the API
  alone — here, forcing `fallback_status` to return `nil`, which turned 7 of 8
  new examples red and correctly left the negative one green. For a view, the
  whole-file revert *is* the right break, because a view has no API.
- **Changing what a result object counts turns green examples red, and widening
  the assertions is the wrong repair.** Adding one synthetic edge made eleven
  passing examples fail. Every one of them was about *which population was read*,
  so each was pointed at `stored_edges` — the collection it had always been about
  — and the new edge got assertions of its own. An example that quietly tolerates
  a new element is an example that has stopped saying anything.
- **`Metrics/ClassLength` counts dead code too.** `WorkflowGraphLayout` came back
  at 201/200, and four of those lines were a copy of `both_reachable?` that
  nothing in the file had ever called. Look for what is unused before looking for
  what to extract — and then extract anyway, because 200/200 is not a margin.
- **`<details>` is the whole disclosure widget** and needs no JavaScript, no
  stylesheet and no Redmine helper. Worth remembering in a plugin that ships no
  assets at all: the alternatives all do.
- **A regexp that spells a quote character is a PostgreSQL-only assertion.**
  PostgreSQL writes `FROM "workflows"`; MySQL and MariaDB write
  `` FROM `workflows` ``. A pattern with `"?` in it matched nothing on six of the
  nine CI cells, and this session shipped it twice before CI said so. Write
  `["`]?` or match the bare name. **The lucky half of it:** the assertion was
  `not_to be_empty`, so an empty list *failed*; the identical mistake under
  `to all(...)` goes **green** over an empty list and proves nothing at all for
  as long as it stands. Grep the specs for that shape before trusting one.
- **"Green on two PostgreSQL hosts" is two of nine, and the other seven include
  every MySQL cell.** Installing MariaDB in this container takes about four
  minutes end to end and the recipe is above. Do it whenever a change touches
  SQL *text* — a spec that reads a statement, a hand-written fragment, an
  assertion about a query plan.
- **`empty?` on a derived collection is rarely the question you mean.** The graph
  screen keyed "this project has its own empty workflow" on `edges.empty?`, which
  is equally true of a project inheriting a generic workflow nobody filled in.
  Whenever a sentence explains *why* a collection is empty, key it on the thing
  that decides the why — here the scope table (INV-3) — never on the emptiness.
  This is the fourth finding in four runs whose whole content is a check that
  asks something adjacent to what it needs to know.
- **404 is for "you named something that is not on offer", not for "there is
  nothing to offer".** A project nobody is a member of has no role to draw a
  workflow for, and answering 404 calls that a missing page. Render, and say what
  the state is — and note that the only reader who can *reach* such a project is
  an administrator, because emptying the membership takes away the permission a
  member would have read it with. A spec for that case has to log in as admin.
- **A `<title>` inside an `<svg>` is not the only `<path>` on a Redmine page.**
  An assertion that "the drawing has no arrow" written as
  `expect(response.body).not_to include('<path d="M ')` fails on core's own icon
  sprite, and then on the plugin's own arrowhead `<marker>`, which lives in
  `<defs>` whether anything uses it or not. Scope to the plugin's `<svg>`, and
  then to what makes a path an *arrow*: its `marker-end`.
- **Redmine caps an issue status name at 30 characters** (`validates_length_of
  :name, maximum: 30`), which is a useful number to know before sizing anything
  that holds one: WP9's node box holds two lines of sixteen. A spec that creates
  a longer status raises `Validation failed: Name is too long`, which reads like
  a bug in the thing under test and is a fixture problem.
- **SVG neither wraps nor measures text**, so anything drawn as `<text>` whose
  width the layout cannot know can run outside the `viewBox` and be clipped with
  no error anywhere. That is why WP9's band of unreachable statuses is separated
  by a dotted rule inside the drawing and captioned in HTML *below* it.
- **A `viewBox` built from node positions clips every curve that bows outside
  them**, silently. Measure the extent over the boxes **and** every point of every
  path; a cubic Bezier lies inside the hull of its four points, so control points
  are a sound bound. The gate for this was broken on purpose and watched to fail.
- **Dummy nodes are for the ordering pass *and* the routing pass.** Inserting a
  dummy in each layer a long edge crosses makes the ordering keep room for it —
  and then drawing that edge as one curve from end to end throws the room away
  and the curve passes through the box of the node in between. Route through the
  dummies.
- **Interpolating a number as `count:` in an I18n key turns it into a
  pluralisation.** `I18n.t(:some_key, count: 3)` makes I18n look for `one`/`other`
  subkeys under that key, and a plain string then answers "translation missing"
  in every language. Name the variable anything else.
- **The working directory persisted into a host checkout and stayed there for
  four tool calls**, so a `grep` of `.rubocop.yml` read *Redmine's* config —
  which has `Metrics: Enabled: false` and no `.github/lint/` at all — and very
  nearly produced a session that believed the size cops were off. The list has
  warned about this trap in three forms already; this is the fourth. `pwd` is
  cheap. Prefix every command with `cd /home/user/redmine_project_workflows &&`.

Everything from here down is carried forward from earlier sessions.

- **An `OR` of ActiveRecord relations does not put every predicate in every
  branch.** Rails factors out what all the branches share, so a statement built
  from four conditions on the same base scope names the base condition and the
  tracker **once**. Any assertion about "how many branches" has to count
  something that is genuinely per branch — here the `project_id` predicate —
  and the only way to know which is to print the SQL from a `rails runner`
  probe before writing the expectation.
- **`Issue#tracker=` asks the workflow nothing when the issue is on the old
  tracker's default status.** It sets `status = nil` on that branch and returns.
  So a query-count measurement, or any example about what a tracker change reads,
  needs an issue on a **non-default** status — and should say why in a comment,
  because the cheap branch makes a broken measurement look like a spectacular
  improvement (ten projects read as 2 statements instead of 22).
- **A one-element list in `where(project_id: [id])` renders as `= 1`, not
  `IN (1)`.** Harmless, but an assertion that greps for `IN` fails on the group
  that happens to hold one project. Match on the column name.
- **`git reset --hard origin/claude/dev` on a fresh container is right, and the
  divergence it discards is not local work.** This container's local
  `claude/dev` was five commits of the *unrelated* `main` lineage; `git checkout`
  reported "5 and 50 different commits each", which reads like something to
  preserve. `git merge-base --is-ancestor A B; echo $?` is the check that cannot
  lie — and the branch the environment minted (here `claude/docs-review-40quew`)
  already pointed at the real remote head, so nothing needed rescuing.

Everything from here down is carried forward from earlier sessions.

- **A gate that has never fired is a claim about nothing, and only a probe tells
  you which kind you have.** Three gates were built in the 0.1.4 session and all
  three were *deliberately made to fail* before being trusted. Two of the three were
  broken when first written and passed anyway: F03's oracle compared two empty
  arrays (see the next entry), and the override-name grep counted seventeen names
  for fifteen overrides. Neither would ever have failed. **Add the gate, then
  break the thing it watches and watch it fail** — with a real change, reverted
  afterwards, not a hypothetical.
- **An example that drives `Issue.new` is not testing the workflow you think it
  is.** A new record resolves transitions from core's `old_status_id = 0`
  pseudo-status, so a rule written out of a real status matches nothing and the
  answer is `[]`. Two `[]`s compare equal, so an oracle example passes while the
  code under test is deliberately broken. Use `Issue.create!` with a current
  status — and create it **before** arranging any rule, because a workflow rule
  can make the save fail.
- **`instance_methods(false)` silently omits what core made private.** Two of the
  methods this plugin shadows are private in core, one of them
  `Issue#workflow_rule_by_attribute`, which decides which fields are read-only or
  required. A reflection-driven gate has to take
  `private_instance_methods(false)` too, or it covers thirteen of fifteen and
  reports success.
- **A SHA256 of all digits is an Integer to YAML.** A digest table has to quote
  its values, or a comparison fails against every host for a reason that has
  nothing to do with the code. Found while probing the drift gate with a
  deliberately wrong all-zero digest.
- **An assertion over a file's whole text fails on the file's own comment.** The
  F12 gate asserted the `Gemfile` did not `include('rspec-rails')`; the `Gemfile`
  explains which gems were removed and names them. Read *declarations*, not text.
  The same trap in a different key: the F13 comment claimed "`grep secrets.` is
  empty" and thereby falsified itself.
- **"No subquery" and "the counts are equal" are the wrong gates**, and both were
  written before being run. F04's correct fix *keeps* an `IN` subquery — `IN` is
  already a semi-join — so the property is "no join, no `DISTINCT`, and the
  subquery does not select `workflows.id`". F10's two query counts are 5 and 3,
  the *small* selection being the more expensive, because a count query is
  skipped when there is nothing to count; the property is a bound. Assert the
  property you can defend, not the one the finding's headline suggests.
- **A new scenario inserted into `dev/check-bulk-js.mjs` between an existing one
  and the `cells` it depends on breaks it.** Exactly the state leak that file's
  own header warns about, met from the other direction. Append after the
  scenario that owns the variable, or `reset()` and build your own.
- **Six `Metrics` limits were crossed in the 0.1.4 session and all six were
  fixed by extracting.** They are already relaxed in `.rubocop.yml` with a stated
  rationale, so crossing one is a real signal. What came out of it, and all of it
  is a genuine improvement rather than placation:
  `Patches::WorkflowsControllerCopy` (the copy screen's four helpers),
  `RedmineProjectWorkflows::MatrixParams` (matrix parameter shaping),
  `RedmineProjectWorkflows::MatrixReporting` (what a write says and logs), and
  `Services::SanitizedPayload` — which was `sanitize_and_count` **duplicated in
  both writers**, so the cop found a real one-rule-in-two-places. Note that a
  module included into a controller must have only private methods.
- **`Rails/ActionControllerFlashBeforeRender` fires on a controller that reads
  its own `flash` back**, e.g. to append a second sentence. The cop is right to
  be suspicious: build a list of messages and assign once.
- **rspec-mocks refuses to stub from an `around` hook** — "the use of doubles
  outside the per-test lifecycle is not supported". For a logger, a real `Logger`
  over a `StringIO` in a `before` hook is better anyway: it asserts the text that
  reaches a log file, where a double would let a formatting change pass.
- **`css_select("label[for=?]", id)` is not a supported form** and raises
  `undefined method 'document' for an instance of String`. Interpolate:
  `css_select("label[for='#{id}']")`.
- **A `FOR UPDATE` statement's row ids travel as bind parameters**, so the SQL
  text cannot say which rows were locked. To assert *coverage* rather than mere
  presence, capture what the locking method returned.
- **A stray `rspec` process from an earlier tool call holds row locks and makes
  the next concurrency example hang.** A two-connection probe that had timed out
  once made the next run look like a deadlock in the fix. `pkill -f rspec` and
  check `pg_stat_activity` before diagnosing.
- **The nine-cell matrix cannot find a timezone defect, and
  `dev/check-backfill.sh` proves it.** That script has long asserted the
  backfilled timestamps are within 600 s of UTC, and it would have caught F09 —
  on a server whose own timezone is not UTC. Every database *container* CI runs
  defaults to UTC, so the drift is zero on all nine cells and always will be.
  Reading `AbstractMysqlAdapter#configure_connection` is what found it. Some
  classes of defect are not reachable by the matrix; know which.
- **A `cd` in a compound command persists and silently redirects the rest of the
  line.** A `cp` restoring a backed-up file after a host-directory `cd` wrote
  nothing and reported nothing useful, leaving the *old* code in the tree with
  the fix only in the scratchpad. Use absolute paths for a restore, always.
- **Neither half of the old timestamp trap was true**, and it is here as a
  correction because it stood in this list, in a migration comment and in
  `docs/DECISIONS.md`. It used to read "PostgreSQL will not cast a text literal to
  a timestamp inside a `SELECT` list, so the backfill uses `CURRENT_TIMESTAMP`".
  Measured on PostgreSQL 16.13: a bare quoted literal in the `SELECT` list of an
  `INSERT … SELECT` **is** coerced to the target timestamp column, no cast needed.
  And `CURRENT_TIMESTAMP` is UTC only on PostgreSQL. Build the timestamp in Ruby:
  `connection.quoted_date`, wrapped in the standard `TIMESTAMP '...'` type
  keyword, which all three accept (finding F09).
- **A scoped `prepend_before_action` DELETES the unconditional registration it
  looks like it is adding to.** ActiveSupport's callback dedupe compares only
  *kind* and *filter* — `Callback#duplicates?` → `matches?(kind, filter)` — and
  `only:` is stored as a separate `:if` condition, so
  `prepend_before_action :require_admin, only: [:edit, :update]` on
  `WorkflowsController` removes core's own unconditional `before_action
  :require_admin` and leaves `index`, `copy` and `duplicate` **ungated**. Read in
  the Rails source at `v6.1.7`, `v7.2.2` and `main`. Nothing in the plugin does
  this — the entry is here because it is precisely the "improvement" a session
  working on the administration screens' callback order reaches for. The safe fix
  is a **guard clause inside the patched finder**, which is what
  `find_trackers_roles_and_statuses_for_edit` now carries (finding F05):
  `User.current` is already correct there, because `ApplicationController`
  registers `user_setup` before `WorkflowsController`'s own callbacks on all
  three supported versions.
- **`say_with_time` prints a row count only if its block returns an Integer.**
  `execute` returns an adapter result object, so migration 003's DELETE from
  Redmine's own `workflows` table printed the elapsed time and no number at all.
  `connection.delete` returns the count (finding F20).

- **A fresh container's local `claude/dev` can have a history unrelated to the
  remote's.** `git pull --ff-only` then aborts with "Not possible to
  fast-forward", and `git status` reports a divergence — "5 and 50 different
  commits" — that looks like real local work to be preserved. It is not:
  `git merge-base claude/dev origin/claude/dev` printed **nothing**, and the two
  branches have different root commits. `git reset --hard origin/claude/dev`.
  What makes this dangerous is the diagnostic: piping an *empty* merge-base into
  `xargs git log --oneline -1` prints **HEAD**, which reads exactly like a merge
  base that happens to be the local head. Use
  `git merge-base --is-ancestor A B; echo $?` instead, which cannot lie.
- **A scoped `prepend_before_action` DELETES the unconditional registration it
  looks like it is adding to.** ActiveSupport's callback dedupe compares only
  *kind* and *filter* — `Callback#duplicates?` → `matches?(kind, filter)` — and
  `only:` is stored as a separate `:if` condition, not in the filter. So
  `prepend_before_action :require_admin, only: [:edit, :update]` on
  `WorkflowsController` removes core's own unconditional `before_action
  :require_admin` and leaves `index`, `copy` and `duplicate` **ungated**. Read in
  the Rails source at `v6.1.7`, `v7.2.2` and `main`. Nothing in the plugin does
  this — the entry is here because it is precisely the "improvement" a session
  working on the administration screens' callback order reaches for, and
  `docs/DECISIONS.md:93` had rejected it for a weaker reason. The fix that is
  safe is a **guard clause inside the patched finder**, which is what
  `find_trackers_roles_and_statuses_for_edit` now carries (finding F05):
  `User.current` is already correct there, because `ApplicationController`
  registers `user_setup` before `WorkflowsController`'s own callbacks on all
  three supported versions.
- **`dev/run.sh` needs `RUBY_VERSION` for the 5.1 host, and the symptom is a
  missing gem.** Without it the ambient Ruby 3.3.6 runs against a bundle
  installed under `ruby/3.2.0`, and the error is
  `bundler: command not found: rspec` — which reads as the Bundler-4
  executables-not-on-PATH trap below and is a wrong Ruby.
  `RUBY_VERSION=3.2.6 dev/run.sh .redmine/5.1-stable-postgresql`.
- **`Metrics/ClassLength`, `Metrics/ModuleLength` and `Metrics/AbcSize` are
  already relaxed in `.rubocop.yml` (200, 250 and 25), with a stated rationale.**
  So crossing one is a real signal rather than a cop to placate, and the honest
  fix is to extract. This session crossed three: `ScopeWriter` at 224/200, which
  produced `ScopeCombinations` — a coherent unit, "the questions a set of exact
  triples can be asked", read-only; `WorkflowsControllerPatch` at 255/250, which
  came back under by moving `combinations_for` into that class and extracting
  `resolved_copy_source`; and `find_tracker_and_role` at 25.08/25, which split
  into itself and `find_role`. Raising a Max, or adding a `.rubocop_todo.yml`
  entry, would have been weakening the gate. Note that the length cops count
  **code** lines only, so the long explanatory comments this repository favours
  are free — and that 25.08 against a limit of 25 is what an extra local variable
  costs, so the margin is thinner than it looks.
- **A new locale key has to exist before the example that asserts it can mean
  anything.** An `expect(flash[:warning]).to eq(I18n.t(:some_new_key))` on the
  old code fails with
  `expected: "Translation missing: en.some_new_key" got: nil` — which *is* a
  valid red (the `nil` is the defect), but only because the right-hand side is
  the thing that is missing. Read which half of such a failure is the finding.
- **Redmine's fixture `roles_005` is *Anonymous* and `roles_004` is *Non
  member*; `roles_003` is *Reporter*, an ordinary role with no member in
  `projects_001`.** `Role.anonymous.consider_workflow?` is false in the
  fixtures and `Role.non_member`'s is true, so a spec about "a role with no
  member" and a spec about "a builtin role that takes part in a workflow" need
  different fixtures.
- **`Role#<=>` sorts by `(builtin, position)`, which is exactly what
  `Role.sorted` orders by.** So `(a + b).uniq.sort` over two `Role.sorted`
  relations is deterministic and matches the scope, on every database — which is
  what `ProjectOptions.visible_roles` relies on rather than re-querying.
- **A `Struct` returned from a service changes every `eq` that asserted the old
  value, and the failure is legible: `expected: 1 got: #<struct ... written=0,
  skipped=1>`.** Five such examples had to move; none was weakened, and saying
  so explicitly in the session report is part of the change, because "I updated
  the tests" and "I weakened the tests" look identical in a diff stat.
- **An empty `<% if %>` branch in ERB passes RuboCop and reads as a mistake.**
  When a new condition means "render nothing here", reorder the branches so the
  empty case is the absent `else` rather than an empty `then`.
- **A partial local that arrives as `nil` is not the same as one that was not
  passed.** `defined?(offered)` is true for a local passed as `nil`, so
  `offered = true unless defined?(offered)` leaves it `nil` — and a `nil` that
  gates a button removes the button silently. Treat both: `if !defined?(x) ||
  x.nil?`.
- **A query count measured inside the counted block can include a fixture
  load.** The first probe of the settings tab read 8 queries and one of them was
  `SELECT "projects".* WHERE id = $1`, which is `projects(:projects_001)` loading
  lazily. Reference every fixture the example needs *before* subscribing. (This
  is the same trap as the memoised-`let` entry further down, met from the other
  direction.)

Everything from here down is carried forward from earlier sessions.

- **A migration reversibility check needs a database built from *core*
  migrations only, and a host that has run the suite has neither.** The suite's
  `maintain_test_schema` dumps `db/schema.rb` **including** the plugin's table
  and column, and `rake db:drop db:create db:migrate` then loads that dump — so
  the plugin's structures are back with no migration bookkeeping behind them,
  `VERSION=0` prints nothing at all, and the check silently proves nothing.
  Redmine does not track `db/schema.rb`, so there is nothing to `git checkout`:
  **delete** it, then `db:drop db:create db:migrate`, then the plugin migrate,
  and only then `VERSION=0`. Redmine records plugin versions in
  `schema_migrations` as `<n>-<plugin_id>` rows, so
  `select version from schema_migrations where version like '%-%'` coming back
  empty is the symptom to check for. CI avoids all of this by running the check
  **before** the suite, on a host built minutes earlier.
- **`bundle exec rubocop` says "command not found: rubocop" even after a clean
  `bundle install`.** Bundler 4 in this container does not put the gem's
  executable on the path. The gem is installed and works — call its `exe/`
  script directly, as in the block above. Ten minutes went into re-running
  `bundle install` and reading its output for an error that was not there.
- **A backgrounded command reports "completed" while it is still running.** The
  harness watches the shell that `nohup … &` returns from, not the process. Both
  a `dev/setup.sh` and a suite run were read as finished on the strength of that
  notification, and the log was mid-`bundle install` in one case and mid-suite in
  the other. Wait for the log to say so — `until grep -q 'examples,' <log>; do
  sleep 5; done` — and never quote a result the log has not printed.
- **A concurrency test needs the fixtures to be *committed*.** The suite runs
  each example inside a transaction, so a second connection sees none of what the
  example arranged. `self.use_transactional_tests = false` for that group, and
  clean up in an `after` hook, because nothing else will.
- **`git stash push -- lib/` is safe only while the fix is uncommitted.** Once
  it is committed the stash has nothing to save, exits 0, says so quietly, and
  the "old code" run is the new code passing itself. Committed fix →
  `git show <old-sha>:<path> > <path>`, run, `git checkout -- <path>`.
- **The Bash working directory persists between calls, and `cd .redmine/<host>`
  makes `git` answer for Redmine's checkout.** A `git stash push` typed from
  there stashes nothing and says "No local changes to save", which reads like the
  plugin's tree being clean. Prefix with
  `cd /home/user/redmine_project_workflows &&`.

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
  an earlier session the C01 view fix once: writing the old version over the file,
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
- **Neither half of the old timestamp trap was true**, and it is here as a
  correction because it stood in this list, in a migration comment and in
  `docs/DECISIONS.md` for a day. It used to read "PostgreSQL will not cast a text
  literal to a timestamp inside a `SELECT` list, so the backfill uses
  `CURRENT_TIMESTAMP`". Measured on PostgreSQL 16.13: a bare quoted literal in
  the `SELECT` list of an `INSERT … SELECT` **is** coerced to the target
  timestamp column, no cast needed. And `CURRENT_TIMESTAMP` is UTC only on
  PostgreSQL — `AbstractMysqlAdapter#configure_connection` sets `sql_auto_is_null`,
  `wait_timeout` and `sql_mode` and **no** `time_zone`, in Rails 6.1, 7.2 and 8.0
  alike, so on MySQL and MariaDB it returns the server's local time and Rails
  reads it back as if it were UTC. Build the timestamp in Ruby:
  `connection.quoted_date`, wrapped in the standard `TIMESTAMP '...'` type
  keyword, which all three accept (finding F09).
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

### Traps from the 2026-08-28 audit session (building a host with no `apt`)

- **The `pg` gem cannot be built in a stock Claude Code web container.**
  `libpq-fe.h` is absent, there is no `apt-get`, and `pg` 1.5's `have_library`
  probe additionally fails on a modern GCC even when headers are supplied by
  hand. A PostgreSQL *server* is present and startable
  (`service postgresql start`), which is useful for testing SQL directly through
  `psql` — that is how "PostgreSQL parses 1,000 nested `OR`s fine" was measured
  — but the Rails adapter cannot be installed.
- **The whole suite runs on SQLite**, and this is the useful fallback: **861
  examples, 0 failures, 9 pending**. Exactly one thing blocks it, and it is a
  real defect rather than a test-environment quirk — the three
  `TIMESTAMP '<literal>'` sites in migration 004, `ScopeCopier` and
  `ProjectWorkflowCopier`. SQLite has no `TIMESTAMP` keyword, so `rake
  redmine:plugins:migrate` aborts inside 004 with `no such column: TIMESTAMP`
  and leaves migrations 001–003 applied. See `2026-08-28-claude-audit.md` F02.
- **`rsync` is not installed**, so `dev/sync.sh` fails at its only command. A
  six-line shell shim over `tar` is enough; `dev/setup.sh` otherwise works.
- **`CoreMethodDigest` runs outside RSpec.** `rails runner` gives all nineteen
  digests in 34.5 ms. Worth knowing before designing anything around it — it is
  what ADR-002's runtime drift check is built on, and it also reveals what the
  gate does *not* cover: the three singleton-class shadows, of which
  `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions` are the two INV-1 rests on.

## Carrying on

Prompt for the next session:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

WP0..WP9 are done. **WP10 is half done**, so "carry on" means, in order:

1. **Read CI for the head and act on it if it is red.** Four of the nine cells
   were run locally and were green; the five MySQL and MariaDB cells have not
   been run anywhere. Nothing in the fixing commit writes SQL text, so a
   difference would be a surprise — but three runs of the WP9 session were red
   on cells no PostgreSQL host can see.
2. **Finish WP10**: the unprefixed-globals convention spec, and the four small
   confirmed defects of `2026-08-28-claude-audit.md` (F01, F02, F04, F05). Its
   other two items are done; *Exact next step* says exactly what each of the
   four means and what already exists.
3. **Then WP11**, which absorbs `VersionHelper.core_sprite_icons?` into
   ADR-002's manifest. That predicate is the interim constant WP10 called for
   and the single place WP11 has to move from.
4. **Before any release, repeat the 45-plugin run.** It is the only environment
   in which the permission-collision gate can fail, and it is the one that found
   the blocker WP10 fixed. The recipe is in *Rebuilding the 45-plugin host*.

Do not invent a work package on top of WP16. Do not re-open the 2026-08-27 run's
"Checked and not filed" table: 24 claims, thirteen rejected or already decided,
four of them by Jan with an explicit instruction not to re-open them. And do not
shorten the `_rules` suffix off either permission name — it is what keeps the
plugin working beside `redmine_custom_workflows`, and `CLAUDE.md`'s
forbidden-constructs table now carries the rule.
