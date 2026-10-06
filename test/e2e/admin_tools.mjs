// The administrator's tools around the workflows: the inventory, the
// diagnostics page, the plugin settings, and what the plugin does to Redmine's
// own administration of roles, trackers and statuses (copying a role or a
// tracker copies its project workflows too; deleting a status a project
// workflow used says so).
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, scopes, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const P = ids.project, BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'];
rails(`Role.where(name: 'E2E copied role').destroy_all; Tracker.where(name: 'E2E copied tracker').destroy_all
       IssueStatus.where(name: 'E2E doomed').each(&:destroy)`);
const t = await e2e('admin_tools');
await t.login('admin');
acceptDialogs(t.page);

// A project decision to look at.
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=copy`);

// Inventory.
await t.go('/project_workflow_inventories');
assert(t, (await t.page.locator('table.list').textContent()).includes('E2E project'), 'the inventory lists the project that decided something');
await t.shot('inventory', 'Admin: the workflow inventory, showing e2e-project Bug x E2E full as an own workflow');
await t.go('/project_workflow_inventories?deviations_only=0');
await t.shot('inventory-all', 'Admin: the inventory with "only deviations" off lists every project');
await t.go('/project_workflow_inventories?project_id[]=999999');
assert(t, (await t.page.locator('#flash_warning').count()) === 1, 'a filter naming a project that does not exist is reported, not silently widened');
await t.shot('inventory-bad-filter', 'Admin: the inventory filtered on a project id that names nothing shows a warning');

// Diagnostics.
await t.go('/project_workflow_diagnostics');
const diag = await t.page.locator('#content').textContent();
assert(t, diag.includes('7.0.1') && /tested against/i.test(diag), 'diagnostics reports Redmine 7.0.1 as a tested version');
assert(t, await t.page.locator('#content .icon-error, #content .icon-not-ok').count() === 0, 'and no failed check');
await t.shot('diagnostics', 'Admin: diagnostics on Redmine 7.0.1, every patch and Deface anchor matched');

// Settings: save new values, see them back; a non-number is not stored as one.
await t.go('/settings/plugin/redmine_project_workflows');
await t.shot('settings', 'Admin: plugin settings with their defaults');
await t.page.fill('input[name="settings[bulk_confirm_threshold]"]', '7');
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#settings form input[type=submit], form[action*="plugin"] input[type=submit]').first().click()]);
await t.settle();
t.check('settings save');
assert(t, await t.page.locator('input[name="settings[bulk_confirm_threshold]"]').inputValue() === '7', 'a saved threshold is shown back');
const stored = rails(`puts Setting.plugin_redmine_project_workflows['bulk_confirm_threshold'].to_json`);
assert(t, stored === '7', `and stored (${stored})`);
await t.go(`/project_workflow_rules/edit?tracker_id[]=${BUG}&role_id[]=${FULL}&project_id[]=${P}`);
assert(t, await t.page.locator(`span.project-workflow-bulk[data-project-workflow-threshold="7"]`).count() > 0, 'the matrix row actions use the new threshold');
// The field is type=number, so a browser will not send "abc"; a hand-built request can.
await t.go('/settings/plugin/redmine_project_workflows');
const sst = await forge(t, 'POST', '/settings/plugin/redmine_project_workflows', {
  'settings[bulk_confirm_threshold]': 'abc', 'settings[bulk_save_confirm_threshold]': '5000',
  'settings[bulk_write_ceiling]': '200000', 'settings[graph_enabled]': '1', 'settings[graph_edge_ceiling]': '2000' });
assert(t, [200, 302].includes(sst), `a forged non-number setting is accepted by core's settings action (HTTP ${sst})`);
await t.go(`/project_workflow_rules/edit?tracker_id[]=${BUG}&role_id[]=${FULL}&project_id[]=${P}`);
const thr = await t.page.locator('span.project-workflow-bulk').first().getAttribute('data-project-workflow-threshold');
assert(t, rails(`puts Setting.plugin_redmine_project_workflows['bulk_confirm_threshold']`) === 'abc', 'the forged "abc" was stored as sent');
assert(t, thr === '50', `and the matrix falls back to the default threshold (got "${thr}")`);
await t.shot('settings-invalid-fallback', `Admin: after saving "abc" as threshold the matrix still works (threshold ${thr})`);
rails(`Setting.plugin_redmine_project_workflows = Redmine::Plugin.find(:redmine_project_workflows).settings[:default]`);

// Copying a role copies its project workflows too.
await t.go(`/roles/new?copy=${FULL}`);
await t.sudo();
await t.page.fill('#role_name', 'E2E copied role');
const wf = t.page.locator('select[name=copy_workflow_from]');
if (await wf.count()) await wf.selectOption(`${FULL}`);
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('input[type=submit][name=commit], input[type=submit]').first().click()]);
await t.settle();
await t.sudo();
t.check('role copy');
const newRole = rails(`puts Role.find_by(name: 'E2E copied role')&.id.to_i`);
assert(t, newRole > 0, 'the role was copied');
const roleRules = rails(`puts [WorkflowTransition.where(role_id: ${newRole}, project_id: nil).count, WorkflowTransition.where(role_id: ${newRole}, project_id: ${P}).count].to_json`);
assert(t, roleRules[0] > 0 && roleRules[1] > 0, `copying the role copied its generic and project rules (${JSON.stringify(roleRules)})`);
await t.shot('role-copied', 'Admin: role copied with "Copy workflow from" E2E full');

// Copying a tracker likewise.
await t.go(`/trackers/new?copy=${BUG}`);
await t.sudo();
await t.page.fill('#tracker_name', 'E2E copied tracker');
const twf = t.page.locator('select[name=copy_workflow_from]');
if (await twf.count()) await twf.selectOption(`${BUG}`);
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('input[type=submit][name=commit], input[type=submit]').first().click()]);
await t.settle();
await t.sudo();
const newTracker = rails(`puts Tracker.find_by(name: 'E2E copied tracker')&.id.to_i`);
const trRules = rails(`puts [WorkflowTransition.where(tracker_id: ${newTracker}, project_id: nil).count, WorkflowTransition.where(tracker_id: ${newTracker}, project_id: ${P}).count].to_json`);
assert(t, newTracker > 0 && trRules[0] > 0 && trRules[1] > 0, `copying the tracker copied its generic and project rules (${JSON.stringify(trRules)})`);
await t.shot('tracker-copied', 'Admin: tracker copied with "Copy workflow from" Bug');

// Deleting a status that a project workflow uses warns and links to the inventory.
// The warning is about workflows the deletion leaves EMPTY: Feature x E2E full
// is given an own workflow whose only rule names the doomed status.
const FEATURE = ids.trackers.Feature;
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${FEATURE}&role_id=${FULL}&rule_type=transitions&source=empty`);
// Fixture written directly: a rule naming a status that is about to be deleted.
const doomed = rails(`s = IssueStatus.create!(name: 'E2E doomed'); WorkflowTransition.create!(project_id: ${P}, tracker_id: ${FEATURE}, role_id: ${FULL}, old_status_id: ${ids.statuses.New}, new_status_id: s.id); puts s.id`);
await t.go('/issue_statuses');
const row = t.page.locator('tr', { hasText: 'E2E doomed' });
await Promise.all([t.page.waitForLoadState('load'), row.locator('a.icon-del, a[data-method=delete]').first().click()]);
await t.settle();
await t.sudo();
t.check('status delete');
const warning = await t.page.locator('#flash_warning').textContent().catch(() => '');
assert(t, rails(`puts IssueStatus.exists?(${doomed})`) === false || rails(`puts IssueStatus.exists?(${doomed})`) === 'false', 'the status was deleted');
assert(t, /inventory/i.test(warning), `and Redmine says which project workflows it touched ("${warning.trim().slice(0, 100)}")`);
await t.shot('status-deleted-warning', 'Admin: deleting a status used by a project workflow shows a warning with a link to the inventory');

rails(`Role.where(name: 'E2E copied role').destroy_all; Tracker.where(name: 'E2E copied tracker').destroy_all`);

// None of this is reachable for a non-administrator.
await t.login('manager');
await t.go('/project_workflow_inventories', { status: 403 });
await t.go('/project_workflow_diagnostics', { status: 403 });
await t.go('/settings/plugin/redmine_project_workflows', { status: 403 });
await t.shot('manager-403', 'Manager: inventory, diagnostics and plugin settings answer 403');

await t.done();
