// Decision q3 (Jan, 2026-10-07): with redmine_itil_priority installed, its
// Impact and Urgency rows stay on Administration -> Workflow -> Fields
// permissions and can be saved, for the generic workflow only. Runs on a host
// that has redmine_itil_priority (the combined GEOxyz host) and says SKIP
// elsewhere. Refusals: manager, reporter, outsider and anonymous.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, assert, forge } from './support.mjs';

const ids = reset();
const installed = rails(`puts Redmine::Plugin.installed?(:redmine_itil_priority)`);
if (installed !== true && installed !== 'true') {
  console.log('SKIP  redmine_itil_priority is not installed on this host');
  process.exit(0);
}
const BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'], NEW = ids.statuses.New;
const url = `/workflows/permissions?role_id[]=${FULL}&tracker_id[]=${BUG}`;
const t = await e2e('neighbour_field_permissions');

await t.login('admin');
await t.go(url);
const rows = await t.page.locator('#workflow_form table td.name').allTextContents();
assert(t, rows.some(r => /Impact/.test(r)) && rows.some(r => /Urgency/.test(r)), 'Impact and Urgency rows are on the generic Fields permissions screen');
await t.shot('rows-shown', 'Admin: core Fields permissions with redmine_itil_priority installed shows the Impact and Urgency rows again');

const impact = t.page.locator(`#workflow_form select[name="permissions[${NEW}][impact_id]"]`);
assert(t, await impact.count() === 1, 'the Impact cell for New is a select');
await impact.selectOption('readonly');
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#workflow_form input[type=submit]').click()]);
await t.settle();
t.check('save');
const stored = rails(`puts WorkflowPermission.where(tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: ${NEW}, field_name: 'impact_id').pluck(:project_id, :rule).to_json`);
assert(t, JSON.stringify(stored) === JSON.stringify([[null, 'readonly']]), `Impact read-only for New is stored, for the generic workflow only (${JSON.stringify(stored)})`);
assert(t, await t.page.locator(`#workflow_form select[name="permissions[${NEW}][impact_id]"]`).inputValue() === 'readonly', 'and shown back after the save');
await t.shot('impact-saved', 'Admin: Impact read-only for New saved on the generic workflow and shown back');

// A field name nothing accepts is still refused (INV-2).
const forged = await forge(t, 'PATCH', '/workflows/update_permissions',
  { 'role_id[]': `${FULL}`, 'tracker_id[]': `${BUG}`, [`permissions[${NEW}][no_such_field]`]: 'readonly' });
assert(t, forged === 302 && rails(`puts WorkflowPermission.where(field_name: 'no_such_field').count`) === 0, `a forged field name nothing accepts is accepted as a request but not written (HTTP ${forged})`);

// A generic save writes no project row.
assert(t, rails(`puts WorkflowPermission.where.not(project_id: nil).where(field_name: 'impact_id').count`) === 0, 'the generic save wrote no project row');

for (const who of ['manager', 'reporter', 'outsider']) {
  await t.login(who);
  await t.go(url, { status: 403 });
  const st = await forge(t, 'PATCH', '/workflows/update_permissions',
    { 'role_id[]': `${FULL}`, 'tracker_id[]': `${BUG}`, [`permissions[${NEW}][impact_id]`]: 'required' });
  assert(t, st === 403, `${who}: the screen and a forged save answer 403 (HTTP ${st})`);
}
await t.shot('outsider-403', 'Outsider (after manager and reporter, same answer): core Fields permissions answers 403');
assert(t, JSON.stringify(rails(`puts WorkflowPermission.where(tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: ${NEW}, field_name: 'impact_id').pluck(:project_id, :rule).to_json`)) === JSON.stringify([[null, 'readonly']]), 'and the rule is unchanged');
await t.anonymous();
await t.go(url);
assert(t, /\/login/.test(t.page.url()), 'anonymous is sent to the login page');

rails(`WorkflowPermission.where(project_id: nil, field_name: 'impact_id', tracker_id: ${BUG}, role_id: ${FULL}).delete_all`);
await t.done();
