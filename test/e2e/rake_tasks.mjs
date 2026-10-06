// The plugin's rake tasks, which have no page: run against the same production
// instance the browser uses, and their effect checked in the browser.
//   redmine_project_workflows:backup FILE=      (FORCE=1 to overwrite)
//   redmine_project_workflows:restore FILE=     (OVERWRITE=1 to replace)
//   redmine_project_workflows:deduplicate_workflow_rules
//   redmine_project_workflows:uninstall         (refused without CONFIRM=yes)
// The full uninstall (every migration reversed, reinstall, restore) is
// rehearsed by dev/check-uninstall.sh on the test database instead, so this
// instance keeps running.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, scopes, acceptDialogs, assert, forge } from './support.mjs';

const REDMINE_DIR = process.env.REDMINE_DIR || 'redmine';
function rake(task, env = {}) {
  const r = spawnSync('bundle', ['exec', 'rake', task], { cwd: REDMINE_DIR, encoding: 'utf8',
    env: { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production', ...env } });
  const out = (r.stdout + r.stderr).split('\n').filter(l => l.includes('redmine_project_workflows') || /^\s/.test(l)).join('\n');
  console.log(`$ rake ${task} ${Object.entries(env).map(([k, v]) => `${k}=${v}`).join(' ')}  -> exit ${r.status}\n${out}`);
  return { status: r.status, out: r.stdout + r.stderr };
}

const ids = reset();
const P = ids.project, BUG = ids.trackers.Bug, FEATURE = ids.trackers.Feature, FULL = ids.roles['E2E full'];
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rpw-e2e-'));
const file = path.join(dir, 'backup.json');
const t = await e2e('rake_tasks');
await t.login('admin');
acceptDialogs(t.page);

// State to back up: an own workflow (copy) and an own EMPTY one.
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=copy`);
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${FEATURE}&role_id=${FULL}&rule_type=transitions&source=empty`);
const rulesBefore = rails(`puts WorkflowRule.where(project_id: ${P}).count`);

// backup: FILE is required; the file is written 0600; an existing file is not overwritten without FORCE.
assert(t, rake('redmine_project_workflows:backup').status !== 0, 'backup without FILE= refuses');
let r = rake('redmine_project_workflows:backup', { FILE: file });
assert(t, r.status === 0 && fs.existsSync(file), 'backup writes the file');
assert(t, (fs.statSync(file).mode & 0o777) === 0o600, `the backup is readable by its owner only (mode ${(fs.statSync(file).mode & 0o777).toString(8)})`);
const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
assert(t, doc.format === 'redmine_project_workflows.backup' && doc.names.projects[String(P)] === 'E2E project' && doc.scopes.length === 2, `and holds the project's two decisions (${doc.scopes.length}), on Redmine ${doc.redmine_version}`);
assert(t, rake('redmine_project_workflows:backup', { FILE: file }).status !== 0, 'a second backup to the same file refuses without FORCE=1');
assert(t, rake('redmine_project_workflows:backup', { FILE: file, FORCE: '1' }).status === 0, 'and overwrites with FORCE=1');

// restore: lose everything, restore, see it back in the browser.
rails(`ProjectWorkflowScope.delete_all; WorkflowRule.where.not(project_id: nil).delete_all`);
await t.go('/projects/e2e-project/settings/project_workflows');
assert(t, !(await t.page.locator('table.project-workflow-settings').textContent()).includes('Own'), 'after losing them every combination follows the generic workflow');
await t.shot('before-restore', 'Admin: the project workflows are gone (every row follows the generic workflow)');
r = rake('redmine_project_workflows:restore', { FILE: file });
assert(t, r.status === 0, 'restore succeeds');
assert(t, scopes(P).length === 2 && rails(`puts WorkflowRule.where(project_id: ${P}).count`) === rulesBefore, `both decisions and all ${rulesBefore} rules are back`);
await t.go('/projects/e2e-project/settings/project_workflows');
const tab = await t.page.locator('table.project-workflow-settings').textContent();
assert(t, tab.includes('Own workflow') && tab.includes('Own empty workflow'), 'the tab shows the own and the own empty workflow again');
await t.shot('after-restore', 'Admin: after rake redmine_project_workflows:restore, the own workflow and the own EMPTY workflow are back');

// A second restore leaves existing workflows alone and says so; OVERWRITE=1 replaces them.
rails(`WorkflowTransition.where(project_id: ${P}, tracker_id: ${BUG}).limit(1).delete_all`);
r = rake('redmine_project_workflows:restore', { FILE: file });
assert(t, r.status === 0 && rails(`puts WorkflowRule.where(project_id: ${P}).count`) === rulesBefore - 1, 'restore without OVERWRITE leaves a workflow the project already has alone');
r = rake('redmine_project_workflows:restore', { FILE: file, OVERWRITE: '1' });
assert(t, r.status === 0 && rails(`puts WorkflowRule.where(project_id: ${P}).count`) === rulesBefore, 'OVERWRITE=1 puts the backed-up rules back');

// A file that is not a backup is refused, and nothing changes.
const junk = path.join(dir, 'junk.json');
fs.writeFileSync(junk, '{"not":"a backup"}');
r = rake('redmine_project_workflows:restore', { FILE: junk });
assert(t, r.status !== 0 && rails(`puts WorkflowRule.where(project_id: ${P}).count`) === rulesBefore, 'restoring a file that is not a backup fails and changes nothing');

// deduplicate: an exact duplicate row is removed, nothing else.
rails(`w = WorkflowTransition.where(project_id: ${P}, tracker_id: ${BUG}).first
  WorkflowTransition.insert_all!([w.attributes.except('id')])`);
assert(t, rails(`puts WorkflowRule.where(project_id: ${P}).count`) === rulesBefore + 1, 'a duplicate row exists');
r = rake('redmine_project_workflows:deduplicate_workflow_rules');
assert(t, r.status === 0 && /deleted 1 duplicate/.test(r.out), 'deduplicate deletes exactly one row');
assert(t, rails(`puts WorkflowRule.where(project_id: ${P}).count`) === rulesBefore, 'and leaves every distinct rule');

// uninstall without CONFIRM=yes refuses and reverses nothing.
r = rake('redmine_project_workflows:uninstall', { FILE: path.join(dir, 'uninstall.json') });
assert(t, r.status !== 0 && /CONFIRM=yes/.test(r.out), 'uninstall without CONFIRM=yes refuses');
assert(t, rails(`puts ActiveRecord::Base.connection.column_exists?(:workflows, :project_id)`) === true || rails(`puts ActiveRecord::Base.connection.column_exists?(:workflows, :project_id)`) === 'true', 'and the schema is untouched');
await t.go('/projects/e2e-project/settings/project_workflows');
await t.shot('after-uninstall-refused', 'Admin: after the refused uninstall the plugin and its workflows are intact');

fs.rmSync(dir, { recursive: true, force: true });
await t.done();
