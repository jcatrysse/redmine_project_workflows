# Installing, upgrading, backing up and removing

- [Installing](#installing)
- [What the migrations do](#what-the-migrations-do)
- [Upgrading](#upgrading)
- [Backing up the project workflows](#backing-up-the-project-workflows)
- [Restoring](#restoring)
- [Uninstalling](#uninstalling)
- [Maintenance](#maintenance)

## Installing

1. Copy the plugin directory into `plugins/` of your Redmine installation.
2. Install dependencies and run the migrations:

   ```
   bundle install
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
   ```
3. Restart Redmine.

`RAILS_ENV` is not optional. Redmine's plugin migration task loads the
environment it is given and defaults to **development**, so leaving it off
migrates the wrong database and reports success.

The only runtime dependency is `deface`, declared as `~> 1.9`. Your Redmine owns
`Gemfile.lock`, so `bundle install` is what applies it; on a host that already
resolved `deface` inside that range, nothing changes.

## What the migrations do

They change Redmine's `workflows` table: add a nullable `project_id` column,
four indexes and a foreign key to `projects`, drop two indexes the new ones
replace, and create two tables of the plugin's own —
`project_workflow_scopes`, which records which projects run their own workflow,
and `project_workflow_write_locks`, which holds a place for two simultaneous
saves to queue. `VERSION=0` removes all of it. That reversal is tested on every
supported Redmine and database on every push.

The size to expect is smaller than "a core table" suggests. `workflows` holds one
row per configured rule, so it grows with trackers, roles and statuses, not with
issues or time. A large installation has tens of thousands of rows there, not
millions. On a synthetic table of 900,000 rows — ten to fifty times larger than
realistic — the whole of the plugin's DDL measured about 7.4 seconds on
PostgreSQL 16, most of it index creation.

Two things to know before running this on a large MySQL or MariaDB installation.
Adding the foreign key is the one operation that rebuilds the table: MySQL
supports the in-place algorithm for it only when `foreign_key_checks` is off, and
Rails does not turn it off. And one migration deletes workflow rows naming a
project that no longer exists — it prints the number, which on an installation
upgrading into this plugin is always 0, because project-specific rows cannot
exist before the column that holds them.

Take a backup, as with any migration that touches a core table.

## Upgrading

**Check your Redmine version first.** 0.0.3 declared a minimum of Redmine 5.0;
0.1.0 and later declare **5.1**. Redmine enforces a plugin's minimum at boot by
raising, so installing this on a Redmine 5.0 leaves an installation that will not
start until the plugin directory is removed. Upgrade Redmine first.

Then the usual:

```
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
```

### Upgrading from 0.0.3 or earlier

Migration 004 creates `project_workflow_scopes` and backfills it: every
(project, tracker, role) that already had rules of its own gets a row saying so.
That turns the old implicit model — *rules exist, therefore this project
overrides* — into the explicit one, and it is why nothing changes for a project
that was already working.

That is checked rather than claimed. `dev/check-release-upgrade.sh` installs the
plugin as it is at the previous release, writes project rules through *that*
release's code, records what it answers when an issue asks which statuses it may
move to and which fields are required, then upgrades and asks again. On every
supported Redmine and database the answers are identical, not one rule is added,
removed or changed, and every project that had its own rules gets a decision for
exactly those combinations.

The migration prints a line per rule type but not a count. To see what it
produced:

```
bundle exec rails runner -e production 'puts ProjectWorkflowScope.group(:rule_type).count'
```

An empty hash means no project had rules of its own before the upgrade, which is
the normal answer on an installation that had not used per-project workflows.

Two things change behaviour afterwards, both deliberately:

- **A project's own rules with no decision recorded now apply to nothing.** The
  backfill gives every such project one, so this only affects rules written
  directly into the database after the upgrade.
- **The status filter and status report are computed per project.** They used to
  be filtered by role as well, which returned nothing for a project with no
  members.

## Backing up the project workflows

A downgrade is not the reverse of an upgrade. Reversing the migrations **deletes
every workflow rule that names a project** and drops the table recording which
projects decided to run their own workflow at all. Both are deliberate (see
[Uninstalling](#uninstalling)), and between them they discard every project
workflow on the installation. The generic workflow is untouched.

So the plugin ships a backup of exactly that population:

```
RAILS_ENV=production bundle exec rake redmine_project_workflows:backup \
  FILE=/var/backups/project-workflows.json
```

One JSON file with every project's decisions and every rule under them, plus the
names of the projects, trackers, roles and statuses they refer to so the file can
be read by whoever has to decide whether to restore it. It refuses to overwrite
an existing file unless you add `FORCE=1`, and it is written at mode 0600.

The file is configuration, not issue data — no issue, journal, user or custom
field *value* is in it — but it does name every project, tracker, role and status
it refers to, so keep it where you keep a configuration dump.

## Restoring

```
RAILS_ENV=production bundle exec rake redmine_project_workflows:restore \
  FILE=/var/backups/project-workflows.json
```

The restore prints what it did. Five things are worth knowing:

- **It leaves alone any project that already has its own workflow** for a tracker
  and a role, and says both how many it left and how many of those differ from
  the backup — which is the number that decides whether `OVERWRITE=1` would
  change anything. `OVERWRITE=1` replaces the rules of those too, keeping the
  decision and its author.
- **A project the file does not mention keeps following the generic workflow.** A
  restore adds; it never hands a project back.
- **It keeps the audit trail** rather than attributing every workflow to whoever
  ran the restore. A user deleted since the backup leaves that column empty.
- **It validates every rule on the way in**, against the trackers, roles,
  statuses and fields that exist now. A status deleted since the backup means the
  rules naming it are refused and counted, not written back as rows pointing at
  nothing.
- **Duplicate rows come back as one row** (see [Maintenance](#maintenance)).

**An interrupted restore is safe to run again, and that is how you recover one.**
Each project, tracker, role and rule type is restored in a transaction of its
own, so a machine that dies halfway leaves every combination either wholly
restored or exactly as it was — never with a decision recorded and no rules under
it, which would be an own empty workflow permitting nothing. If a combination
fails, the restore finishes the others, names the ones that failed and exits
non-zero so a script notices. Run the same command again, with the same `FILE=`
and no `OVERWRITE=1`: what completed is left alone and what failed is done
properly this time.

Running a completed restore twice is safe too. The second run reports that
everything was left alone and changes nothing.

## Uninstalling

Reverse the migrations *before* removing the plugin directory. The plugin's
tables and its column on `workflows` are not removed by deleting the code.

One task does the whole procedure in the order that makes it survivable:

```
RAILS_ENV=production bundle exec rake redmine_project_workflows:uninstall \
  FILE=/var/backups/project-workflows.json CONFIRM=yes
```

It prints what is about to be discarded and how much of it there is, refuses to
go on without `CONFIRM=yes` typed in full, writes the backup and reads it back
before anything is destroyed, and only then reverses the migrations. It also
re-checks immediately before reversing: if a workflow changed while it was
waiting for your confirmation, it refuses rather than destroying something the
backup does not hold. A run refused at the confirmation writes no file and
changes nothing. `SKIP_BACKUP=1` skips the backup for an operator who has a
database dump instead.

The step it ends with is Redmine's own, and you can run it by hand:

```
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0
```

That deletes every project-specific rule before dropping the `project_id` column.
The delete is deliberate and has to precede the column drop: removing the column
with those rows still in the table would leave stock Redmine reading every one of
them as a *generic* rule. Your generic workflow is untouched.

An own **empty** workflow does not survive either, and leaves no trace: the
decision row is the only place it was ever recorded, and that table goes too.
This is the one thing a downgrade loses silently, and it is why the backup holds
decisions and not only rules.

**Check the output, and check the `RAILS_ENV`.** There is no way back from this
except the file the task just wrote.

If you remove the plugin directory *without* running this, Redmine keeps working —
core only ever reads and writes the `project_id IS NULL` rows — but every project
rule stays in the table, inert, and comes back into force the moment the plugin
is reinstalled.

### Downgrading, and coming back

There is no "downgrade to the previous version": the migrations run to
`VERSION=0` and back up again. Going back to a release before the plugin means
the uninstall above. Coming back afterwards is three steps:

1. put the plugin directory back and `bundle install`;
2. `RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows`;
3. `RAILS_ENV=production bundle exec rake redmine_project_workflows:restore FILE=…`.

Every step of that round trip runs in CI on every push, on all three Redmine
versions and all three databases (`dev/check-uninstall.sh`).

## Maintenance

Neither Redmine nor this plugin has a unique constraint on `workflows` — the key
would have to include two nullable columns, and every supported database treats
NULLs in a unique index as distinct (see [design.md](design.md)). Duplicate rows
make a matrix cell render as a mixed dropdown instead of a checkbox.

The plugin no longer produces them: every workflow write takes a lock before it
rewrites anything, so two administrators saving the same matrix queue rather than
collide. Redmine's own workflow screens have the same race and no such lock, and
a database can carry duplicates from before this version or from another plugin.
To clean them up:

```
bundle exec rake redmine_project_workflows:deduplicate_workflow_rules
```

It removes only rows identical in every column, so it cannot change what any
workflow permits. Two field permissions that agree on everything but the rule are
a contradiction rather than a duplicate, and are left for you to settle.
