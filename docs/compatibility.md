# Compatibility

Every fact in this file lives in
[`lib/redmine_project_workflows/compatibility.yml`](../lib/redmine_project_workflows/compatibility.yml),
and a spec fails if the two disagree.

## Tested combinations

- **Redmine 5.1, 6.1 and 7.0**, each against **PostgreSQL, MySQL and MariaDB**.
  Nine combinations, all of them green before a change lands.
- **Ruby 3.2** for Redmine 5.1, **Ruby 3.3** for 6.1 and 7.0 — the versions CI
  uses.

Redmine 5.1 is the declared minimum as of 0.1.0. It used to be 5.0, which nothing
ever tested.

## On a Redmine that is not one of those three

The plugin installs and runs. It declares a minimum version and no maximum,
because a version range would turn a Redmine upgrade into an installation that
refuses to boot until somebody deletes the plugin directory.

What it does instead is measure. The plugin reimplements more than twenty of
Redmine's own methods — there is no `super` to call, because core's workflow
queries carry no project column — so it records a fingerprint of each of them for
every Redmine it has been tested against, and compares on an unknown one. It does
the same for the five places it adds something to one of Redmine's own screens,
checking that each still finds the markup it attaches to. When one does not,
Redmine says nothing at all and the screen simply comes out missing a control.

That gives three answers, in the log at startup, on the plugin's own screens and
on the diagnostics page:

| Answer | What it means |
|---|---|
| **Verified** | This Redmine is one the plugin is tested against. Nothing is measured and nothing is said. |
| **Not verified, no differences found** | Nobody has tested this Redmine, but every method the plugin copied is identical to the newest one that was. |
| **Not verified, differences found** | One or more of those methods has changed. The diagnostics page names them and says where Redmine defines them. |

The third is a warning, not a refusal. The plugin keeps working and so do the
screens an administrator would use to put it right. What the check proves is
precise and worth stating plainly: that the *bodies* the plugin copied are
unchanged. It does not prove Redmine still calls them the same way. It is
evidence, not a guarantee.

Anything but the first puts a banner on the screens where a workflow rule is
about to change: both administration matrices, the summary, the copy screen, the
two project matrices and the project's Workflow tab. It names the state and, for
an administrator, links to the diagnostics page. A verified Redmine says nothing
anywhere, which is what keeps the banner worth reading.

## The diagnostics page

**Administration → Project workflows → Diagnostics**, reached from the action bar
of every screen in the plugin's administration area. It has no entry of its own
in Redmine's administration menu: the plugin costs that menu one line, and this
is a page you are sent to rather than one you go looking for.

Besides the compatibility answer above, it reports three things whose wrong
answer is otherwise silent:

- **Permissions.** Two plugins can register the same permission name. Redmine
  answers with whichever was registered first, and the loser's screens then
  refuse everybody, administrators included, with nothing in any log. The page
  says whether the names this plugin registered are the ones Redmine answers
  with. This is not hypothetical — it happened to this plugin on a real
  installation, which is why both permissions are named
  `*_project_workflow_rules`.
- **Patches.** Which of Redmine's classes the plugin changes, and whether each
  change is in place. A patch that is not applied leaves Redmine behaving as it
  does without the plugin, which looks like the plugin doing nothing rather than
  like an error.
- **Screens.** Which of Redmine's own screens the plugin adds to. A screen that
  looks wrong is worth reporting even when everything here is listed as in order:
  the list says what was registered, not what was placed.

## Living beside other plugins

Two points of contact are worth knowing about if you run a large plugin set.

**`Issue#new_statuses_allowed_to`.** The plugin answers this itself, for projects
that follow the generic workflow too, rather than falling back to Redmine's own
query — Redmine's carries no `project_id` and would let one project read
another's rules. If another plugin patches the same method, load order decides
which of you wins.

**Redmine's own workflow screens.** The plugin routes
`WorkflowTransition.replace_transitions` and
`WorkflowPermission.replace_permissions` through its own writers. It has to, or a
generic save would delete projects' rules along with the generic ones. Those
writers validate against server-built lists, which is narrower than core: core
accepts any run of digits as a field name, the plugin accepts only a core field
or an existing custom field id. A rejected entry is dropped before anything is
deleted, so it leaves the rule it names alone rather than clearing it, and the
screen says so instead of reporting a save. In practice this only shows up for a
hand-built request; the matrices cannot produce a rejected value.
