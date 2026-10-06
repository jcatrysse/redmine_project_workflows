// Administration -> Project workflows: the menu entry and the cross-link from
// Redmine's own Workflow screen, the summary, the transitions and field
// permissions matrices over a selection of several projects, the state actions
// over that selection, the row/column bulk actions with undo, the write ceiling,
// and the refusals: bad selections, non-administrators, anonymous.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, ruleCount, scopes, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const P = ids.project, Q = ids.private, BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'];
const t = await e2e('admin_rules');
const two = `tracker_id[]=${BUG}&role_id[]=${FULL}&project_id[]=${P}&project_id[]=${Q}`;

await t.login('admin');
let dialogs = acceptDialogs(t.page);

// Entry points.
await t.go('/admin');
assert(t, await t.page.locator('#admin-menu a[href="/project_workflow_rules"], a.project-workflow-rules[href="/project_workflow_rules"], #main-menu a[href="/project_workflow_rules"], #sidebar a[href="/project_workflow_rules"], #content a[href="/project_workflow_rules"]').count() >= 1,
  'Administration lists "Project workflows"');
await t.shot('admin-menu', 'Admin: "Project workflows" in the administration menu, with the core workflows icon');
await t.go('/workflows/edit');
assert(t, await t.page.locator('div.contextual a[href="/project_workflow_rules"]').count() === 1, "Redmine's own Workflow screen links across to Project workflows");

// Summary.
await t.go('/project_workflow_rules');
assert(t, await t.page.locator('table.list').count() === 1, 'the summary renders its table');
await t.shot('summary', 'Admin: Project workflows summary (generic), counts per tracker and role');

// Transitions matrix over two projects: both inherit, so Save writes nothing for them.
await t.go(`/project_workflow_rules/edit?${two}`);
assert(t, /2/.test(await t.page.locator('.project-workflow-scope').textContent()), 'the scope panel speaks about the two selected workflows');
await t.shot('matrix-two-inheriting', 'Admin: transitions matrix over e2e-project and e2e-private, both follow the generic workflow');

// Give both their own workflow (copy) from the scope panel.
dialogs.length = 0;
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('.project-workflow-scope a', { hasText: 'Give own workflow (copy of the generic one)' }).click()]);
await t.settle();
t.check('enable over selection');
assert(t, dialogs.length === 1, 'the action asked for confirmation');
const generic = ruleCount({ tracker: BUG, role: FULL });
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === generic && ruleCount({ project: Q, tracker: BUG, role: FULL }) === generic,
  `both projects got a copy of the ${generic} generic rules`);
await t.shot('matrix-two-own', 'Admin: both projects now have an own workflow; the matrix is editable for the selection');

// Bulk action: set the "New" row to No, see the counter, undo it, set it again and save.
const newRow = t.page.locator('table.transitions-always tbody tr').filter({ has: t.page.locator('td.name', { hasText: /^\s*New\s+Yes/ }) }).first();
const rowNo = newRow.locator('td.name a.project-workflow-bulk-action').getByText('No', { exact: true });
await rowNo.click();
const undo = t.page.locator('#project-workflow-bulk-undo');
assert(t, await undo.isVisible(), 'a row action shows the unsaved-change counter with Undo');
const undoText = (await undo.textContent()).replace(/\s+/g, ' ').trim();
await t.shot('bulk-row-no', `Admin: the New row set to No by one click; the counter says "${undoText.slice(0, 80)}"`);
await undo.locator('a.project-workflow-bulk-undo-action').click();
const restored = await newRow.locator('input[type=checkbox]:checked:not([disabled])').count();
assert(t, restored > 0, `Undo puts the row back (${restored} ticked again)`);
await rowNo.click();
const otherGeneric = ruleCount({ tracker: BUG, role: FULL });
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('form[action="/project_workflow_rules/update"] input[type=submit]').click()]);
await t.settle();
t.check('save over selection');
const newId = ids.statuses.New;
const fromNew = rails(`puts WorkflowTransition.where(project_id: [${P}, ${Q}], tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: ${newId}).count`);
assert(t, fromNew === 0, `the save removed every "from New" rule in both projects (${fromNew} left)`);
assert(t, ruleCount({ tracker: BUG, role: FULL }) === otherGeneric, 'and left the generic workflow alone (INV-1)');
await t.shot('matrix-saved', 'Admin: after Save, the New row is empty for both projects');

// Field permissions over the same selection.
await t.go(`/project_workflow_rules/permissions?${two}`);
await t.shot('permissions-two', 'Admin: field permissions matrix over the two projects (inheriting, Save leaves them alone)');

// Empty, then return both to the generic workflow.
await t.go(`/project_workflow_rules/edit?${two}`);
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('.project-workflow-scope a', { hasText: 'Empty' }).first().click()]);
await t.settle();
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === 0 && scopes(P).length === 1, 'Empty removes the rules and keeps both decisions');
await t.shot('matrix-two-empty', 'Admin: both projects own EMPTY workflows');
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('.project-workflow-scope a', { hasText: 'Return to the generic workflow' }).first().click()]);
await t.settle();
assert(t, scopes(P).length === 0 && scopes(Q).length === 0, 'Return removes both decisions');

// The write ceiling: an action that would write more rules than allowed is refused.
rails(`Setting.plugin_redmine_project_workflows = Setting.plugin_redmine_project_workflows.merge('bulk_write_ceiling' => '5')`);
await t.go(`/project_workflow_rules/edit?${two}`);
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('.project-workflow-scope a', { hasText: 'Give own workflow (copy of the generic one)' }).click()]);
await t.settle();
assert(t, scopes(P).length === 0 && scopes(Q).length === 0, 'above the write ceiling nothing is written');
assert(t, await t.page.locator('#flash_error').count() === 1, 'and the refusal is shown');
await t.shot('ceiling-refused', 'Admin: with bulk_write_ceiling = 5, giving two projects a copy of 30 rules each is refused before anything is written');
rails(`Setting.plugin_redmine_project_workflows = Setting.plugin_redmine_project_workflows.merge('bulk_write_ceiling' => '200000')`);

// Bad selections answer 404 and write nothing.
for (const [what, q] of [['a tracker that names nothing', `tracker_id[]=999999&role_id[]=${FULL}`],
  ['a float-shaped tracker id', `tracker_id[]=1e5&role_id[]=${FULL}`],
  ['a role that names nothing', `tracker_id[]=${BUG}&role_id[]=999999`],
  ['a project that names nothing', `tracker_id[]=${BUG}&role_id[]=${FULL}&project_id[]=999999`]]) {
  await t.go(`/project_workflow_rules/edit?${q}`, { status: 404 });
  assert(t, true, `404 for ${what}`);
}
await t.shot('bad-selection-404', 'Admin: a selection naming a tracker that does not exist answers 404');
const forged = await forge(t, 'PATCH', '/project_workflow_rules/update',
  { 'tracker_id[]': '1e5', 'role_id[]': `${FULL}`, [`transitions[${newId}][${ids.statuses['In Progress']}][always]`]: '1' });
assert(t, forged === 404, `a forged save for tracker "1e5" is refused (HTTP ${forged})`);

// Non-administrators.
for (const who of ['manager', 'reporter', 'outsider']) {
  await t.login(who);
  await t.go('/project_workflow_rules', { status: 403 });
  await t.go(`/project_workflow_rules/edit?${two}`, { status: 403 });
  const st = await forge(t, 'POST', '/project_workflow_scopes', { 'tracker_id[]': `${BUG}`, 'role_id[]': `${FULL}`, 'project_id[]': `${P}`, rule_type: 'transitions', source: 'copy' });
  assert(t, st === 403, `${who}: the administration area and its scope action answer 403 (HTTP ${st})`);
}
await t.shot('manager-403', 'Manager (every project permission, not an administrator): the administration area answers 403');
assert(t, scopes(P).length === 0, 'and nothing was written');
await t.anonymous();
await t.go('/project_workflow_rules');
assert(t, /\/login/.test(t.page.url()), 'anonymous is sent to the login page');
await t.shot('anonymous-login', 'Anonymous: the administration area redirects to the login page');

await t.done();
