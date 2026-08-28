# Review run — 2026-08-28 — Claude (whole-stack compatibility, Redmine 5.1)

- **Reviewer:** Claude Code (Opus), in a Claude Code on the web container
- **Commit reviewed:** `e7f1e90`
- **Ran the test suite:** yes — Redmine 5.1.13-stable, PostgreSQL 16, Ruby 3.2.6.
  Twice: **861 examples / 0 failures** with this plugin alone, and
  **861 examples / 69 failures** with 44 neighbouring plugins beside it. Every
  one of those 69 is attributed below. Only 5.1/PostgreSQL was run — one of the
  nine supported cells.
- **Scope covered:** *not* the usual review dimensions. This run answers one
  question Jan asked: **does this plugin still work when every other plugin in
  his repository is installed next to it on Redmine 5.1**, and in particular
  whether the older `alias_method` patching those plugins use collides with
  ours. It therefore covers: whole-stack boot, migrations, page-level smoke
  testing of 68 URLs, the `project_settings_tabs` chain, permission and route
  registration collisions, and this plugin's own suite run inside that host.
- **Scope NOT covered:** Redmine 6.1 and 7.0; MySQL and MariaDB; anything
  requiring JavaScript in a browser; the *other* plugins' own test suites; and
  any dimension of the normal review prompt (nil handling, i18n, N+1, …) except
  where a compatibility problem surfaced one. Two plugins in the repository were
  not installed and are named in F09. `redmine_vault`, which Jan asked to
  exclude, **does not exist in the repository** — nothing was excluded on that
  account.

## Summary

The stack runs. Forty-five plugins — this one, forty-three of Jan's, and one
local stand-in — boot together on Redmine 5.1 in production mode, every
migration applies, and 68 pages across core and the plugins answer without a
single server error. The project settings page shows **27 tabs contributed by
15 different plugins**, which is the headline positive result: the four
neighbours that take `project_settings_tabs` over with a 2013-era
`alias_method` chain, the three that override it with `super`, and this
plugin's `ProjectsController.helper` all compose correctly, in both load
orders. The design decision Jan pointed at — patch beside `ProjectsHelper`,
never inside it — was **measured, not assumed**: switching this plugin back to
`ProjectsHelper.prepend` on the running stack turns every project's settings
page into an HTTP 500 (F03). It is the single most valuable thing this run
confirmed.

Three things are wrong, and one of them is serious. **`redmine_custom_workflows`
registers a permission with the same name as ours** — `manage_project_workflow`
— and because it loads first, its (empty) registration wins. The effect is that
**nobody, not even an administrator, can save a project workflow**: every write
action of this plugin answers 403, and the role form shows the checkbox twice
with the same HTML id. That accounts for 53 of the 69 spec failures and is
finding F01. Second, this plugin decides "does the host draw SVG icons?" by
asking `respond_to?(:sprite_icon)`, and on Redmine 5.1 **two** neighbours define
that method as a compatibility shim — so the plugin takes the Redmine 6 branch
on a Redmine 5.1 host and the "no rules here" marker disappears from the
workflow summary page (F02). Third, `redmine_view_issue_description` puts a new
permission in front of every issue page; that is its declared purpose, but it
means this plugin's issue-form specs cannot run beside it unmodified (F04), and
it is worth Jan knowing what it does to a fresh install.

The remaining findings are about **other** plugins and are recorded because
they stopped the stack from booting at all until they were worked around. Two
are hard boot failures on a stock installation (F05, F06), one is inert code
that silently does nothing (F07), and one is a missing third-party dependency
(F08). None of them is this plugin's to fix; they are here so that "install
everything and it works" is a reproducible claim rather than a hope.

**Counts:** blocker 1 · major 3 · minor 3 · nit 1 · question 1

### How the host was built (so this is reproducible)

```
Redmine 5.1-stable @ 16eb9e6 (5.1.13) · PostgreSQL 16 · Ruby 3.2.6 · Rails 6.1.7.10
45 plugins in plugins/, migrated with rake redmine:plugins:migrate
RAILS_ENV=production, eager loading on (this is what caught F06)
```

Plugin sources were cloned from `github.com/jcatrysse/*` at their default
branches on 2026-08-28, except where a finding below says otherwise. The full
list with commit hashes is in the appendix.

---

### F01 — `manage_project_workflow` collides with `redmine_custom_workflows`, and every write action of this plugin answers 403

- **Status:** fixed
- **Severity:** blocker
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `init.rb:49` (`permission :manage_project_workflow`), against
  `redmine_custom_workflows/init.rb:31`
- **Invariant touched:** none directly — but it disables everything INV-3 exists to make possible

**What is wrong**

`redmine_custom_workflows` — a plugin Jan runs, upstream at
`anteo/redmine_custom_workflows`, in his fork since at least 2024 — declares:

```ruby
permission :manage_project_workflow, {}, require: :member
```

An empty action hash, outside any `project_module`. This plugin declares a
permission of the **same name** with the action list that makes its screens
reachable. Redmine keeps `Redmine::AccessControl.@permissions` as a flat array
and `AccessControl.permission(name)` returns the **first** match; plugins load
in alphabetical directory order, and `redmine_custom_workflows` sorts before
`redmine_project_workflows`. So the registration that wins is the one with no
actions and no module.

`Project#allowed_actions` is built from `AccessControl.allowed_actions(name)`,
which reads that first registration. `project_workflows/enable`,
`update_transitions`, `update_permissions`, `inherit` and `clear` are therefore
in **no** permission's action list, `ApplicationController#authorize` denies
them, and it denies them for administrators too — `User#allowed_to?` returns
`false` before it reaches its `return true if admin?` line, because
`Project#allows_to?` answered false first.

The read side survives: `view_project_workflow` is unique to this plugin, so
`transitions`, `permissions`, `compare` and `graph` still render.

**Why it matters**

On Jan's stack, today: open a project's *Workflow* settings tab as an
administrator, click *Give this project its own workflow* → **403 You are not
authorized to access this page**. The tab renders, the buttons are there, and
every one of them is dead. A project can be looked at and never changed, which
is the plugin with its whole purpose removed.

There is a second, smaller symptom on `/roles/:id/edit`: two checkboxes are
rendered with `id="role_permissions_manage_project_workflow"`, duplicate HTML
ids on the same page, and ticking one does not tick the other. Which of the two
the role actually stores is not obvious to the person ticking it.

**How I verified it**

Live, on the running stack:

```
POST /projects/alpha/workflow/scope?role_id=3&tracker_id=1&rule_type=transitions&source=copy
  -> 403, log says "Filter chain halted as :authorize rendered or redirected"
     (session user: admin, id=1)
```

and by introspection in `rails runner`:

```
view_project_workflow:   found module=issue_tracking actions=["projects/settings", ...5 entries]
manage_project_workflow: found module=  actions=[]
```

and by the suite: commenting that one line out of the host's copy of
`redmine_custom_workflows/init.rb` takes this plugin's suite from
**69 failures to 16**. Nothing else changed between the two runs.

`grep -c 'id="role_permissions_manage_project_workflow"'` on the rendered role
form returns 2.

**Suggested direction**

The name has to stop being shared, and this plugin is the one that should move:
it is alpha, it has never been released (`main` carries 0.0.3, there is no
tag), and the neighbour has had the name for years. Anything else — asking
users to patch a third-party plugin, or authorizing outside Redmine's
permission map — is worse.

Worth deciding as part of it: whether `view_project_workflow` moves too, so the
pair stays symmetric, or whether only the colliding half is renamed. A rename
needs a migration over `roles.permissions` (a serialized array) even at alpha,
because Jan's own installations already hold the old name.

Also worth doing regardless of which name is chosen: a spec that fails if any
permission this plugin registers is not the one `AccessControl.permission`
returns for that name. The collision was invisible for as long as it existed
because nothing asserted the registration *won*.

**Resolution:** fixed. Answered **B** by Jan on 2026-08-28 — rename both, so the
pair stays symmetric — and built the same day.

`view_project_workflow` and `manage_project_workflow` are now
`view_project_workflow_rules` and `manage_project_workflow_rules`, in `init.rb`,
the two controllers, the three views, the eight locale files (**keys only** —
the label text an administrator reads is unchanged, so nothing was retranslated
and `spec/locales_spec.rb` parity is untouched) and the specs. The ivar
`@manage_project_workflow` moved with them, because a line reading
`@manage_project_workflow = allowed_to?(:manage_project_workflow_rules, ...)`
looks like a typo.

**Migration 006 carries existing grants across**, per name, and refuses to guess
where it cannot know. A role may hold `:manage_project_workflow` because of the
*neighbour*, and the stored symbol says nothing about which plugin it was
granted for: renaming it would take the neighbour's permission away, and adding
ours beside it would widen what that role may do. So the migration asks whether
anything else still registers the legacy name — `AccessControl.permissions.any?`,
which is the question that actually decides ambiguity and stays right if the
neighbour is renamed or removed — and where the answer is yes it leaves the
grant alone and prints what to grant instead. The name that is unambiguous still
moves; one collision does not strand the pair. Reversible (INV-8): `down` maps
back, and `VERSION=0` was run on 5.1, 6.1 and 7.0 with leftover columns `[]`,
plugin tables `[]` and plugin `schema_migrations` rows `[]`.

**Red on the old code, and stated precisely.** The new example in
`plugin_conventions_spec.rb` — *owns every permission name it registers* —
**cannot fail on this plugin's own CI**, where it is the only plugin installed;
that is written into the example's own comment rather than left for a reader to
discover. The evidence that matters is on the multi-plugin host: this plugin's
suite went from **69 failures to 10** on the 45-plugin Redmine 5.1 host with the
rename alone, and the 53 that disappeared are exactly this finding. The
migration's own judgement is covered by
`spec/models/permission_rename_migration_spec.rb` (7 examples); replacing
`claimed_elsewhere?` with `false` turns *leaves the ambiguous grant alone* red,
which was run and watched.

Observed on the real host: `rake redmine:plugins:migrate` on the 45-plugin
installation printed *"another plugin still registers manage_project_workflow;
leaving role grants of it alone. Grant manage_project_workflow_rules to the roles
that should have it."* — the designed behaviour, against the real neighbour.

---

### F02 — `respond_to?(:sprite_icon)` is not a test for "Redmine 6", and two neighbours make it answer wrongly on 5.1

- **Status:** fixed
- **Severity:** major
- **Confidence:** confirmed
- **Category:** portability
- **Where:** `lib/redmine_project_workflows/version_helper.rb:15`
  (`project_workflows_svg_icons?`), and the same expression in
  `spec/controllers/project_workflows_controller_spec.rb:500` and
  `spec/integration/deface_overrides_spec.rb:129`
- **Invariant touched:** none

**What is wrong**

`project_workflows_svg_icons?` decides whether the host draws SVG sprite icons
by asking whether a `sprite_icon` helper exists. `CLAUDE.md` says version
differences should live in one place, and they do — but the *question* that
place asks is about a method name, and a method name is not owned by Redmine.

On Redmine 5.1 two neighbours define it:

1. the **`redmineup` gem** (1.1.13), pulled in by every RedmineUP plugin —
   agile, checklists, contacts, drive, people, questions, reporter, resources,
   tags, zenedit — which does
   `ApplicationHelper.prepend(Redmineup::Patches::Compatibility::SpritePatch)`
   behind a correct `if Redmine::VERSION.to_s < "6"` guard;
2. **`redmine_ai_triage`**, whose `Patches::IconsCompatibilityPatch` does
   `ApplicationHelper.include(self)` on 5.1 only.

Both shims return the label and nothing else, which is right for *their* views.
For this plugin they flip `project_workflows_svg_icons?` to `true` on a host
that has no sprite sheet.

`redmine_ai_triage` asks the question the robust way, three files away in the
same host: `RedmineAiTriage::Compatibility.sprite_icons?` is
`[Redmine::VERSION::MAJOR, MINOR].first >= 6`.

**Why it matters**

Most of the consequences are invisible, because both shims degrade to the
label and 5.1's `icon-*` CSS class still draws the picture. One is not.
`project_workflows_summary_count_body` returns the bare count instead of 5.1's
`icon-not-ok` span as soon as `svg_icons?` is true, and
`project_workflows_summary_count_class` adds `decoration-red`, a class Redmine
5.1's stylesheet does not define (`grep -c decoration-red
public/stylesheets/application.css` → 0).

So on `/workflows` — the administration summary of every tracker × role — a
combination with **no rules at all** renders as:

```html
<a title="Edit" class="decoration-red" href="/workflows/edit?role_id=1&amp;tracker_id=1">0</a>
```

a plain, unstyled `0`, where stock Redmine 5.1 renders a red "not ok" marker
and where the cells this plugin does *not* re-render would still show one. The
signal that says "this combination is empty" is gone from the one page whose
job is to show it at a glance.

**How I verified it**

On the running stack, `GET /workflows` as admin: `decoration-red` appears 3
times, `icon-not-ok` 0 times, and the three cells are the three zero-count
cells. In `rails runner`:

```
ApplicationController.helpers.respond_to?(:sprite_icon) -> true
method owner -> Redmineup::Patches::Compatibility::SpritePatch
  at redmineup-1.1.13/lib/redmineup/patches/compatibility/sprite_patch.rb:5
```

In the suite, 6 of the 16 non-F01 failures are this, and they persist with
`redmine_ai_triage` disabled (the gem shim is enough on its own):

```
project_workflows_controller_spec.rb:656  draws the collapsible legend the way the host draws icons
project_workflows_controller_spec.rb:670  draws the field group expander the way the host draws icons
deface_overrides_spec.rb:336              the summary page draws the inventory link the way the host draws icons
deface_overrides_spec.rb:396              the multiselect toggle ... transitions page
deface_overrides_spec.rb:409              the multiselect toggle ... field permissions page
deface_overrides_spec.rb:604              draws the link the way the host draws icons
```

with messages of the form `expected "<a class=\"icon icon-list\" ...>Workflow
inventory</a>" to include "<svg"`.

**Suggested direction**

Ask the version, not the method. The three call sites — one in the helper, two
in specs — should agree, and the specs should be asking the same question the
production code asks rather than restating it, so that a neighbour cannot make
both wrong in the same direction and hide the mismatch.

**Resolution:** fixed, both halves. `VersionHelper.core_sprite_icons?` is now
`::Redmine::VERSION::MAJOR >= 6` — a fact no neighbouring plugin owns — and
`project_workflows_svg_icons?` is a one-line wrapper over it, so the views are
unchanged. The three spec sites that restated `respond_to?(:sprite_icon)` now
call that same predicate; in `deface_overrides_spec.rb` the helper moved into a
small module because two of its groups need it.

Three new examples in `plugin_conventions_spec.rb`, and between them they are
**red on every supported version**, which was measured rather than reasoned:
with the old predicate restored, 5.1 fails *is not fooled by a neighbouring
plugin defining sprite_icon* and 7.0 fails *is not fooled by a context that has
no sprite_icon at all*; the third, a grep for the construct in `app/` and `lib/`,
fails on both. All four runs were executed and the failures read.

The user-visible half is confirmed gone on the 45-plugin host: the six icon
failures in the suite are green, and `GET /workflows` no longer emits
`decoration-red` on a Redmine 5.1 host.

---

### F03 — `ProjectsController.helper` is load-bearing: confirmed by experiment, not by argument

- **Status:** fixed
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** docs
- **Where:** `lib/redmine_project_workflows/patches/projects_helper_patch.rb:36-79`
- **Invariant touched:** none — but this is the forbidden-constructs row about `ProjectsHelper.prepend`

**What is wrong**

Nothing is wrong. This is recorded because the comment in `apply!` and the last
row of `CLAUDE.md`'s forbidden-constructs table state a failure mode that had
never been observed on a real multi-plugin host, and now it has. A finding that
says "the reasoning was right" is worth as much as one that says it was wrong,
and it costs the next reader the experiment.

On this stack, `ProjectsHelper`'s **own** `project_settings_tabs` is not core's.
It is `redmine_wiki_extensions`' `_with_wiki_extensions` copy, sitting on top of
alias chains from `redmine_reporter`, `redmine_questions`,
`redmine_contacts_helpdesk`, `redmine_contacts`, `redmine_checklists` and
`redmine_agile`. Three further plugins — `redmine_issue_view_columns`,
`redmine_custom_workflows`, `redmine_ai_triage` — and this one override the
method with `super` from the controller's helper set. All ten compose:

```
ProjectsController._helpers#project_settings_tabs
  RedmineProjectWorkflows::Patches::ProjectsHelperPatch   (this plugin)
  RedmineIssueViewColumns::ProjectHelperPatch
  RedmineCustomWorkflows::Patches::Helpers::ProjectsHelperPatch
  RedmineAiTriage::Patches::ProjectsHelperPatch
  ProjectsHelper                                          (wiki_extensions' aliased copy)
```

and the settings page renders **27 tabs from 15 plugins**.

Change `ProjectsController.helper(self)` to `ProjectsHelper.prepend(self)` and
restart, and the same page is an **HTTP 500**. `ProjectsHelper.ancestors` then
begins with this plugin's module, `redmine_wiki_extensions` (which loads after
`redmine_project_workflows`, alphabetically) aliases **our** method into
`ProjectsHelper`, and its `super` has nowhere to go:

```
NoMethodError: super: no superclass method `project_settings_tabs' for #<ActionView::Base>
```

**Why it matters**

It matters as evidence, not as a defect. The next person who finds
`ProjectsController.helper` odd and "simplifies" it to a prepend will take down
every project's settings page on Jan's installation, and this finding names the
exact command that shows it.

**How I verified it**

Edited the *host's* copy of the file (never the repository's), restarted the
production server, and requested `/projects/alpha/settings` as admin: 500. The
`rails runner` reproduction is above. Restored the file, restarted, requested
again: 200, 27 tabs.

**Suggested direction**

Nothing to change in code. Possibly a sentence in the `apply!` comment saying
this was measured on 2026-08-28 against a 45-plugin host, and naming
`redmine_wiki_extensions` as the neighbour that springs the trap — the comment
currently argues from the general shape, and one named example is easier to
trust.

**Resolution:** the suggested paragraph is in `apply!`, with both measurements
(27 tabs from 15 plugins against HTTP 500), the exact `NoMethodError`, and
`redmine_wiki_extensions` named as the neighbour that springs it. No behaviour
changed and no test was added: there is nothing here a test on a single-plugin
host could assert, which is the point of writing the measurement down instead.

---

### F04 — `redmine_view_issue_description` gates every issue page behind a new permission, and this plugin's issue-form specs cannot run beside it

- **Status:** adjusted
- **Severity:** major
- **Confidence:** confirmed
- **Category:** test-quality
- **Where:** `spec/integration/deface_overrides_spec.rb:564-690`,
  `spec/integration/issue_status_help_spec.rb`, against
  `redmine_view_issue_description/lib/.../issues_controller_patch.rb:371-380`
- **Invariant touched:** none

**What is wrong**

`redmine_view_issue_description` prepends `IssuesController` and answers 403 to
`show`, `edit` and `update` unless the reader is an administrator, is the
assignee, is a watcher holding `view_watched_issues`, or holds
`view_issue_description` for the issue's tracker. That is the plugin's declared
purpose and it works exactly as designed.

This plugin's issue-form specs use Redmine's own fixtures, in which no role
holds `view_issue_description` — the permission did not exist when the fixtures
were written. Eleven examples therefore get 403 where they expect 200.

This is a **test-environment** finding, not a product defect: nothing this
plugin ships is wrong, and on a real installation where the permission has been
granted the two plugins coexist. It is filed at *major* rather than *minor*
because it is the reason "run the suite on the real stack" is not currently a
thing anybody can do, and that is the check most likely to catch the next F01.

**Why it matters**

Two separate consequences, and they should not be confused.

For the repository: `dev/run.sh` against a host that also carries
`redmine_view_issue_description` reports 11 failures that mean nothing, and a
reader has to know that before they can weight the run.

For Jan's installation, worth stating plainly because it is not obvious from
the plugin's name: on a Redmine where this plugin is installed and no role has
been given `view_issue_description`, **no non-admin can open any issue at all**
— not the issue page, not the edit form. Anyone installing it onto an existing
Redmine has to grant the permission to every role in the same maintenance
window.

**How I verified it**

Disabling `redmine_view_issue_description`'s `init.rb` in the host takes the
suite from 16 failures to 6; the 10 that disappear are exactly the
`IssuesController` and `issue_status_help` examples. The failure message is
uniformly `expected the response to have status code :ok (200) but it was
:forbidden (403)`. The gate itself is four lines of `PrependMethods` calling
`vid_description_access?`.

**Suggested direction**

The specs should be able to state what they need rather than inheriting it.
Something that grants the role under test whatever permissions the *host's*
registered plugins demand for `issues#show` and `issues#edit`, computed rather
than listed, so that a neighbour added next year does not need the specs edited
again. A hard-coded `add_permission! :view_issue_description` would work today
and be wrong the next time.

Whatever shape it takes, it belongs behind a "is this permission registered at
all" check, so that the plugin's own CI — where the neighbour is absent — is
unaffected.

**Resolution:** fixed, but **not the way this finding suggested, because that
way is impossible** — hence `adjusted` rather than `fixed`.

The finding asked for the demanded permissions to be *computed* rather than
listed, so that a neighbour added next year would need no edit. There is nothing
to compute from. `redmine_view_issue_description` declares
`permission :view_issue_description, {}` — an **empty** action hash — and puts
the gate in a `prepend` on `IssuesController`. `Redmine::AccessControl` therefore
holds nothing at all connecting that permission to `issues#show`, and no amount
of reflection can derive it. A reviewer's suggested direction that turns out to
be unbuildable is worth saying so about, rather than quietly building something
else.

What was built is the second half of the suggestion, which does hold:
`HostPluginPermissionHelpers#grant_host_issue_page_permissions` in
`spec/spec_helper.rb` carries a **named** list of one, and grants only what
`Redmine::AccessControl.permission(name)` says the host actually registered. On
this plugin's own CI, where the neighbour is absent, it does nothing whatsoever
— so it cannot widen what any example is granted there. The comment says all of
this, including that a future neighbour needs one more name.

Measured: with it, the 45-plugin Redmine 5.1 host runs **872 examples, 0
failures**. Without it, the same host leaves the 10 examples this finding names.

The operational half of the finding — that installing
`redmine_view_issue_description` onto an existing Redmine locks every non-admin
out of every issue until each role is granted `view_issue_description` — is not
this repository's to fix and is repeated in the session report for Jan.

---

### F05 — A stock install of Jan's plugin set does not boot: `redmine_contacts` and the `redmineup` gem both define the route `auto_complete_taggable_tags`

- **Status:** wont-fix
- **Severity:** major
- **Confidence:** confirmed
- **Category:** dependency
- **Where:** not this plugin — `redmine_contacts/config/routes.rb:97` against
  `redmineup-1.1.13/config/routes.rb:5`
- **Invariant touched:** none

**What is wrong**

`redmine_contacts` (Jan's fork, `1ca1289`) declares:

```ruby
match 'auto_completes/taggable_tags' => 'auto_completes#taggable_tags',
      :via => :get, :as => 'auto_complete_taggable_tags'
```

RedmineUP moved that route into the shared `redmineup` gem somewhere between
1.1.0 and 1.1.5. Its `Gemfile` says only `gem 'redmineup'`, unpinned, so a
fresh `bundle install` resolves 1.1.13 and Rails refuses the duplicate name:

```
ArgumentError: Invalid route name, already in use: 'auto_complete_taggable_tags'
```

This is not a warning. Redmine does not start — not the server, not
`rake db:migrate`, nothing.

**Why it matters**

Anyone rebuilding Jan's installation from the repositories, on a machine where
`Gemfile.lock` is not carried over, gets a Redmine that will not boot and an
error message that names neither plugin. His running installation is presumably
fine because its lockfile pins an older `redmineup`; that safety disappears the
first time anyone runs `bundle update`.

**How I verified it**

It was the second thing that stopped this exercise. The host boots after
commenting out that one line in `redmine_contacts/config/routes.rb`; the gem's
route is identical, so nothing is lost.

**Suggested direction**

Either drop the line from the fork (the gem provides it, and the fork already
depends on the gem) or pin `redmineup` in that plugin's `Gemfile` to the last
version that did not define it. Dropping the line is the smaller and more
durable of the two.

**Resolution:** `wont-fix` **here** — it is `redmine_contacts`' line to delete,
not this repository's. Recorded because a Redmine that does not boot is the
first thing anyone rebuilding Jan's installation meets, and the error names
neither plugin. Jan owns the fork; the smaller and more durable of the two
options is dropping the route from it, since the `redmineup` gem the plugin
already depends on provides an identical one.

---

### F06 — `redmine_wiki_custom_fields` breaks production boot, and does nothing when it does not

- **Status:** wont-fix
- **Severity:** major
- **Confidence:** confirmed
- **Category:** dependency
- **Where:** not this plugin — `redmine_wiki_custom_fields`, `443875f`
- **Invariant touched:** none

**What is wrong**

Two defects in one small plugin, and the second is the interesting one.

*It stops production boot.* `lib/redmine_wiki_custom_fields/version.rb` defines
`RedmineWikiCustomFields::VERSION`. Redmine puts every plugin's `lib/` on
Zeitwerk's eager-load path, and Zeitwerk expects `version.rb` to define
`Version`:

```
Zeitwerk::NameError: expected file .../version.rb to define constant
RedmineWikiCustomFields::Version, but didn't
```

In development this never fires (nothing references the constant). In
production, where `eager_load` is on, Redmine does not start.

*And when it is made to boot, it does nothing.* Both of its entry points are
constructs `CLAUDE.md` already lists as forbidden, for exactly this reason:

- `Rails.configuration.to_prepare` in `init.rb` and in
  `lib/redmine_wiki_custom_fields.rb` — Redmine loads `init.rb` from *inside* a
  `to_prepare` block, after the `:add_to_prepare_blocks` initializer has
  consumed the array, so neither block ever runs;
- a `Rails::Engine` subclass declared in that same file — Rails collected its
  railties long before, so the engine is never registered and its
  `initializer` never runs.

**Why it matters**

`WikiPage` gets no custom field support at all, and there is no error anywhere
to say so. The plugin appears in the plugin list with a version number and does
nothing.

**How I verified it**

Deleting `version.rb` from the host copy is what let the stack boot. Then, in
`rails runner`:

```
CUSTOM_FIELDS_TABS names: [... 13 entries, none of them "WikiPageCustomField"]
WikiPage.method_defined?(:custom_field_values)   -> false
WikiPage.method_defined?(:available_custom_fields) -> false
WikiPage.ancestors matching /WikiCustomFields/   -> []
RedmineWikiCustomFields.constants                -> [:Engine, :WikiPagePatch, :Api]
```

The patch module is loaded — eager loading sees it — and never included.

**Suggested direction**

Not this repository's work. Filed here because the same two constructs are in
this plugin's forbidden table with the same reasoning, and a neighbour that
demonstrates the failure is the clearest possible argument for keeping the rule.
Worth telling whoever maintains that plugin: move the constant, and apply the
patches from the body of `init.rb`.

**Resolution:** `wont-fix` **here** — `redmine_wiki_custom_fields` is a separate
repository. Recorded in full because both of its defects are constructs
`CLAUDE.md` already forbids in this plugin for exactly the reasons this
neighbour demonstrates, and a live example is worth more than the rule: the
plugin boots nothing in production and, once made to boot, does nothing at all.
The evidence here is ready to be pasted into an issue there.

---

### F07 — `create_tags` is registered by two plugins under different modules

- **Status:** wont-fix
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** dependency
- **Where:** not this plugin — `redmine_questions/init.rb:63` against
  `redmineup_tags/init.rb:48`
- **Invariant touched:** none

**What is wrong**

The same shape as F01, one level less harmful. `redmine_questions` declares
`permission :create_tags, {}` inside `project_module :questions`;
`redmineup_tags` declares `permission :create_tags, {}` inside
`project_module :issue_tracking`. Neither has actions, so no controller action
is lost — but `AccessControl.permission(:create_tags)` returns the first, and
`redmine_questions` sorts first.

**Why it matters**

`User.current.allowed_to?(:create_tags, project)` now asks whether the
**Questions** module is enabled. On a project with issue tracking and no
Questions module, `redmineup_tags` refuses to let a user create a new tag —
`issue_tags_controller.rb:34` and `issue_tags_api_controller.rb:30` — even
though the role holds the permission. The role form also renders two checkboxes
with `id="role_permissions_create_tags"`.

**How I verified it**

By enumerating `Redmine::AccessControl.permissions` on the booted host and
grouping by name: `manage_project_workflow` ×2 and `create_tags` ×2, and
nothing else in the whole 45-plugin set. `grep -c
'id="role_permissions_create_tags"'` on `/roles/3/edit` returns 2. The
behavioural consequence is read from the two controllers, **not** executed —
that half is `probable`, and the registration collision itself is confirmed.

**Suggested direction**

RedmineUP's own two plugins to reconcile; nothing here to change. Recorded
because whatever spec F01 grows should catch this class of problem for any
future permission this plugin adds, and because the count of collisions across
the whole stack — exactly two — is a useful number to have written down.

**Resolution:** `wont-fix` **here** — two RedmineUP plugins to reconcile. The
class of problem *is* now guarded on this side: `plugin_conventions_spec.rb`
asserts that every permission this plugin registers is the one
`AccessControl.permission` answers with, so the next name this plugin adds
cannot lose a collision silently (see F01). Nothing here can assert anything
about `create_tags`, which this plugin does not register.

---

### F08 — Two plugins in the repository cannot run on Redmine 5.1 from their default branch

- **Status:** wont-fix
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** operability
- **Where:** not this plugin

**What is wrong**

Three separate version problems, found while assembling the host:

1. **`redmine_ai_triage`** on `main` (`6946f0a`) declares
   `REQUIRED_REDMINE_SERIES = '7.0'`, so on 5.1 Redmine aborts with
   `PluginRequirementError`. Its branch
   `claude/plugin-redmine-compatibility-2mbcx3` declares a 5.1–7.0 range and
   was used instead; that is the branch every ai_triage result in this file
   refers to.
2. **`redmine_custom_workflows`** on `master` requires Redmine ≥ 6.0.0. Its
   `5.x` branch (`0398974`) requires ≥ 4.1.0 and was used.
3. **`redmine_wiki_extensions`** on `main` requires Redmine ≥ 6.0.0. Its
   `Redmine-5.1` branch (`e0b64b3`) requires ≥ 4.0.0 and was used.

**Why it matters**

Only for reproducibility, and for whoever next tries to stand this stack up: a
naive "clone every repository's default branch" produces a Redmine 5.1 that
refuses to start, and the first error names only `redmine_ai_triage`.

**How I verified it**

Each was a boot abort with the plugin named in the message.

**Suggested direction**

Nothing for this repository. Worth a line in whatever document describes Jan's
installation, saying which branch each of the three is deployed from.

**Resolution:** `wont-fix` **here** — branch selection for three neighbouring
plugins. Worth a line in whatever document describes Jan's installation; the
three branches are named above and in the appendix table.

---

### F09 — What was installed, and what was not

- **Status:** wont-fix
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** docs
- **Where:** the host, not the code

**What is wrong**

Not a defect — the honest statement of what this run's "everything works"
covers, so the claim can be weighted.

**Installed and registered: 45 plugins.** This one, 43 of Jan's, and one local
stand-in.

**Not installed, and why:**

- **`redmine_vault`** — Jan asked for it to be excluded. It **is not in the
  repository at all** — the repository listing for this account contains no
  repository of that name, under `jcatrysse` or anywhere else it can see.
  Nothing was excluded on its account, and if Jan runs it, it was not part of
  this test.
- **`redmine-email-oauth`** — has no `init.rb`. It is a patch file and a
  `Gemfile.local` fragment, not a Redmine plugin, and it changes the mail
  library rather than registering with Redmine.
- **`jira2redmine_migration`, `jcatrysse/redmine`** — a migration toolkit and a
  fork of Redmine itself; neither is a plugin.
- **`redminetrustteam/*`** — a different organisation. Two repositories are
  visible there; one duplicates a plugin already installed from `jcatrysse`.
  Not installed, because Jan said *his* repository.

**Substituted:** `redmine_datetime_custom_field` declares
`requires_redmine_plugin :redmine_base_deface`, a Planio plugin that is not in
Jan's repository and that this container could not reach. A **13-line local
shim** was written to stand in for it: it loads the `deface` gem (already in
the bundle), keeps Zeitwerk from eager-loading `plugins/*/app/overrides`, and
loads those files itself — the two things the real plugin has to do, because
Redmine plugins are not Rails railties and deface's own `load_all` only walks
railties. Whether the real plugin does anything *else* that
`redmine_datetime_custom_field` depends on was not established, so that one
plugin's behaviour is the least-tested thing in this run.

**Also worth knowing:** `redmine_datetime_custom_field` defines a top-level
`ApplicationRecord` class on Redmine 5 (in `init.rb`, where 5.1 core has none).
Every plugin on the host now inherits that definition. Nothing broke, and it
would break loudly rather than quietly if a second plugin defined it
differently.

**Why it matters**

An unstated gap reads as "clean". These are the gaps.

**How I verified it**

`Redmine::Plugin.all.size` → 45 on the booted host. Repository list from
`list_repos`. The shim is 13 lines and is quoted in full in the session report.

**Suggested direction**

If Jan's real installation carries `redmine_base_deface`, the honest next run
installs it rather than the shim. If it does not, then
`redmine_datetime_custom_field` cannot be loading on his installation either,
and that is worth knowing.

**Resolution:** `wont-fix` — a record of what this run did and did not cover,
not a defect. The one actionable item in it is a question for Jan and is
repeated in the session report: **does the installation carry
`redmine_base_deface`?** If it does, the honest next compatibility run installs
the real plugin instead of this session's 13-line shim. If it does not, then
`redmine_datetime_custom_field` cannot be loading there either, because its
`requires_redmine_plugin` would abort the boot.

---

### F10 — Should this plugin's permission pair be renamed together or singly?

- **Status:** fixed
- **Severity:** question
- **Confidence:** n/a
- **Category:** ux
- **Where:** `init.rb:45-53`
- **Invariant touched:** none

**What is wrong**

F01 forces `manage_project_workflow` to be renamed. `view_project_workflow`
does not collide with anything on this stack and could keep its name — but then
the pair reads asymmetrically on the role form, where the two appear side by
side, and a reader has no way to tell that the asymmetry is a scar rather than
a distinction.

**Why it matters**

Permission names are what an administrator reads when configuring a role, and
they are what a role record stores. Whichever is chosen, changing it again
later costs a second migration over `roles.permissions`.

**How I verified it**

Not a defect; a choice surfaced by F01.

**Suggested direction**

Jan's call. Two shapes worth considering, with a name that is collision-free
against all 45 plugins on this host:

- rename **only** the colliding half, smallest possible migration, asymmetric
  pair;
- rename **both**, e.g. `view_project_workflow_rules` /
  `manage_project_workflow_rules`, symmetric and descriptive of what the
  permission actually governs, at the cost of migrating a name that did not
  have to move.

**Resolution:** answered **B** by Jan on 2026-08-28 and built the same day —
`view_project_workflow_rules` and `manage_project_workflow_rules`. Logged under
*Decided (Jan)* in `docs/DECISIONS.md`. The work is described in F01's
resolution; nothing separate was needed for this half beyond carrying the second
name through the same migration, which is one entry in its `RENAMES` hash.

---

## Appendix — the plugins installed, with commits

Cloned from `github.com/jcatrysse/<name>` on 2026-08-28. The directory name is
the plugin id from `Redmine::Plugin.register`, which differs from the
repository name in three cases (noted).

| plugin id | repository | commit | branch |
| --- | --- | --- | --- |
| bless_this_redmine_sso | bless-this-redmine-sso | 54fb053 | master |
| computed_custom_field | redmine_plugin_computed_custom_field | c9cb1df | master |
| redmine_agile | redmine_agile | 27f685e | master |
| redmine_ai_summary | redmine_ai_summary | a6f1a93 | main |
| redmine_ai_triage | redmine_ai_triage | 6946f0a → compat branch | `claude/plugin-redmine-compatibility-2mbcx3` (F08) |
| redmine_base_deface | — | — | **local 13-line shim** (F09) |
| redmine_checklists | redmine_checklists | e052567 | master |
| redmine_contacts | redmine_contacts | 1ca1289 | master, one route line removed (F05) |
| redmine_contacts_helpdesk | redmine_contacts_helpdesk | 155ed5e | master |
| redmine_custom_workflows | redmine_custom_workflows | 0398974 | `5.x` (F08) |
| redmine_datetime_custom_field | redmine_datetime_custom_field | ed1e1b2 | master |
| redmine_depending_custom_fields | redmine_depending_custom_fields | fa0adaf | main |
| redmine_description_macros | redmine_description_macros | 0dc2f6b | main |
| redmine_drawio | redmine_drawio | 67fa4ca | master |
| redmine_drive | redmine_drive | 5ffcbb1 | master |
| redmine_editauthor | redmine_editauthor | 6b22e8f | master |
| redmine_extended_api | redmine_extended_api | 132fff5 | main |
| redmine_helpdesk_contact_sync | redmine_helpdesk_contact_sync | f3f5a56 | main |
| redmine_impersonate | redmine_impersonate | 845446c | master |
| redmine_inline_edit_issues | redmine_inline_edit_issues | a0865eb | master |
| redmine_issue_field_visibility | redmine_issue_field_visibility | 4139400 | master |
| redmine_issue_templates | redmine_issue_templates | a3c30b0 | master |
| redmine_issue_todo_lists2 | redmine_issue_todo_lists2 | 2c6f653 | master |
| redmine_issue_view_columns | redmine_issue_view_columns | f921c4d | master |
| redmine_itil_priority | redmine_itil_priority | a97bab7 | master |
| redmine_ldap_sync | redmine_ldap_sync | b1b0fbf | master |
| redmine_mail_digest | redmine_mail_digest | e734469 | main |
| redmine_mermaid_macro | redmine_mermaid_macro | e48be41 | master |
| redmine_more_previews | redmine_more_previews | b564c08 | main |
| redmine_parent_child_filters | redmine_parent_child_filters | 29c1676 | main |
| redmine_paste_as_wiki_tables | redmine_paste_as_wiki_tables | 7e4a161 | master |
| redmine_people | redmine_people | 4f5f91a | master |
| redmine_project_workflows | **this plugin** | e7f1e90 | `claude/dev` |
| redmine_questions | redmine_questions | 60593bf | master |
| redmine_reporter | redmine_reporter | b1d1736 | master |
| redmine_reporter_dashboards | redmine_reporter_dashboards | eddb8fa | main |
| redmine_resources | redmine_resources | 1f25729 | master |
| redmine_stealth | redmine_stealth | 3b2ed40 | master |
| redmine_subtask | redmine_subtask | 4dab83d | develop |
| redmine_tint_issues | redmine_tint_issues | a7f80d1 | master |
| redmine_view_issue_description | redmine_view_issue_description | e289ec6 | main |
| redmine_wiki_custom_fields | redmine_wiki_custom_fields | 443875f | main, `version.rb` removed (F06) |
| redmine_wiki_extensions | redmine_wiki_extensions | e0b64b3 | `Redmine-5.1` (F08) |
| redmine_zenedit | redmine_zenedit | 98723de | master |
| redmineup_tags | redmine_tags | 17c3f9e | master |

## Appendix — what was exercised

68 URLs as an administrator, none returning 5xx. Core: dashboard, projects,
issues, activity, search, gantt, calendar, admin index, plugins, projects,
info, settings, roles, trackers, issue statuses, custom fields, enumerations,
users, groups, auth sources, the three workflow administration screens, project
overview/settings/issues/new issue/activity/wiki/news/documents/files/roadmap/
time entries/boards/copy, an issue page and its edit form, `/my/page`,
`/my/account`. This plugin: the two matrices, the comparison screen, the
drawing, the inventory, both workflow-map endpoints, and the settings tab.
Neighbours: agile board, contacts, deals, questions, drive, issue templates,
people, LDAP sync admin, custom workflows, issue view columns, and twelve
plugin settings pages.

Also checked and clean: **no duplicate named routes** across the whole stack
(`Rails.application.routes.routes.map(&:name).tally`), **30 project modules**
with no name collisions, **0 `Completed 500`** in the production log across the
whole session, and every one of this plugin's fifteen Deface overrides still
matching — the only `deface_overrides_spec.rb` failures were F02 and F04, and
none of them was an override failing to find its anchor. **INV-9 holds on a
45-plugin host.**

One expected, harmless error in the log: `pandoc --version failed`, from
`redmine_more_previews` looking for a converter this container does not have.
