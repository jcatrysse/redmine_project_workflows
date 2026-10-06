# Browser scenarios

What no other gate in this repository does: the plugin **rendered and clicked**,
on a real Redmine, by a real browser.

The suite asserts what the code does. These scripts assert what an administrator
and a project manager *see and can do* — that the settings tab offers the right
three actions, that taking a workflow over changes what a real issue permits,
that a request naming a tracker that does not exist is refused before anything is
written, and that a Redmine the plugin has not been tested against says so on
every screen where somebody is about to change a rule.

**Not a CI gate.** They need a running server with seeded data, which CI does not
build. They are for a session that has changed something a person looks at, and
for the evidence in a session report. `docs/review/findings/2026-08-29-claude-browser.md`
is what one run produced.

## Running them

```bash
# 1. A host with the plugin in it (dev/README.md), then a development database.
#    Redmine's development environment wants the `listen` gem, which is not in
#    this bundle: set config.cache_classes = true in
#    config/environments/development.rb and nothing needs reloading.
cd .redmine/5.1-stable-postgresql
cat >> config/database.yml <<'YML'

development:
  adapter: sqlite3
  database: db/development.sqlite3
  timeout: 5000
YML
RAILS_ENV=development bundle exec rake generate_secret_token db:migrate
RAILS_ENV=development REDMINE_LANG=en bundle exec rake redmine:load_default_data
RAILS_ENV=development bundle exec rake redmine:plugins:migrate

# 2. The installation the scenarios expect.
RAILS_ENV=development bundle exec rails runner \
  plugins/redmine_project_workflows/dev/e2e/seed.rb

# 3. The server, detached.
(RAILS_ENV=development setsid nohup bundle exec rails server \
   -b 127.0.0.1 -p 3000 -e development > /tmp/redmine-dev.log 2>&1 < /dev/null &)

# 4. Playwright against the pre-installed Chromium — never `playwright install`.
cd - && cd dev/e2e && npm init -y && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install playwright
./run-all.sh
```

`run-all.sh` resets the project workflows between scenarios, so the order does
not matter and a failed run leaves nothing behind.

## The scenarios

| File | What it is about |
| --- | --- |
| `admin.mjs` | The administration area: one menu entry and not two (F07), the action bar, the diagnostics page and the way back, no banner on a verified host, the generic matrix |
| `manager.mjs` | A project manager, not an administrator: the settings tab, taking a workflow over through the real confirm dialog, editing and saving the matrix, and the rule they removed still standing in what a neighbouring project inherits (INV-1) |
| `effect.mjs` | What all of it is *for*: the status dropdown on a real issue, through all three states of INV-3 — inherit, own empty, and back |
| `guard.mjs` | Who may reach what (anonymous, a plain user, a viewer, another project), and the twelve bad-selection shapes of F03 |
| `screens.mjs` | The inventory, the copy screen and its refusal, the comparison screen, the drawing, and the bulk controls |

## Regenerating the screenshots

`docs/images/` is produced from the same host:

```bash
RAILS_ENV=development bundle exec rails runner \
  plugins/redmine_project_workflows/dev/e2e/seed.rb
RAILS_ENV=development bundle exec rails runner \
  plugins/redmine_project_workflows/dev/e2e/seed_docs.rb   # realistic names, a workflow worth drawing
node dev/e2e/docshots.mjs
```

`seed_docs.rb` renames the scenario projects and replaces one workflow with a
plain path plus two shortcuts, because Redmine's default everything-to-everything
workflow draws as spaghetti and makes a poor illustration. Run `seed.rb` again
afterwards if you want to run the scenarios: they expect the scenario names back.

Not in the list, and worth adding when somebody has the time: the bulk row and
column actions *driven* rather than merely present, a second browser, and a
mobile viewport.

## Two things the scripts do on purpose

**Every page is checked for JavaScript errors and failed requests**, not only for
the markup asserted on. A screen that renders correctly and breaks its own
JavaScript is the failure mode Deface-style additions produce, and it is
invisible to a request spec. `net::ERR_ABORTED` is filtered out: navigating away
cancels whatever the previous page still had in flight.

**Links are followed rather than URLs built.** Redmine gives ids 1 and 2 to the
built-in Non-member and Anonymous roles, so `role_id=1` names a role no project
offers and the plugin refuses it — correctly. A first version of these scripts
hardcoded it and reported that refusal as a defect.
