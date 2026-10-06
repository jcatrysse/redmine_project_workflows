// Project settings -> Workflow: the tab, and the three state actions behind it
// (give own workflow as a copy, give own empty workflow, return to the generic
// one, and empty an own workflow). As manager (manage permission), viewer
// (view only), reporter (neither), outsider (no membership) and admin.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, scopes, ruleCount, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const P = ids.project, BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'];
const tab = '/projects/e2e-project/settings?tab=project_workflows';
const t = await e2e('project_settings_tab');

// --- manager: every action ---------------------------------------------------
await t.login('manager');
let dialogs = acceptDialogs(t.page);
await t.go(tab);
const table = t.page.locator('table.project-workflow-settings');
assert(t, await table.count() === 1, 'manager sees the Workflow tab with its table');
const rows = await table.locator('tbody tr').count();
assert(t, rows === 9, `one row per enabled tracker x role held in the project (3 x 3), got ${rows}`);
assert(t, (await t.page.locator('#content').textContent()).includes('Follows the generic workflow'),
  'every combination starts as "Follows the generic workflow"');
await t.shot('manager-inherits', 'Manager: the Workflow tab, every combination follows the generic workflow, actions offered');

const bugFull = table.locator('tbody tr', { hasText: 'E2E full' }).filter({ hasText: 'Bug' });
const transitionsCell = bugFull.locator('td.project-workflow-transitions');
await Promise.all([t.page.waitForURL(/project_workflows/), transitionsCell.getByText('Give own workflow (copy of the generic one)').click()]);
await t.settle();
t.check('give own workflow (copy)');
assert(t, dialogs.length === 1, 'the browser asked for confirmation before taking the workflow over');
const generic = ruleCount({ tracker: BUG, role: FULL });
const own = ruleCount({ project: P, tracker: BUG, role: FULL });
assert(t, own === generic && own > 0, `the project got a copy of the generic rules (${own} of ${generic})`);
assert(t, (await transitionsCell.textContent()).includes('Own workflow'), 'the cell now says "Own workflow"');
await t.shot('manager-own-copy', 'Manager: Bug x E2E full transitions taken over as a copy; the cell offers Empty and Return');

// Empty it: the scope stays, the rules go (INV-3, third state).
dialogs.length = 0;
await Promise.all([t.page.waitForURL(/project_workflows/), transitionsCell.getByText('Empty', { exact: false }).first().click()]);
await t.settle();
t.check('empty own workflow');
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === 0, 'emptying deletes the project rules');
assert(t, scopes(P).length === 1, 'and keeps the decision (scope) in place');
assert(t, /Own empty workflow/i.test(await transitionsCell.textContent()), 'the cell says "Own empty workflow"');
await t.shot('manager-own-empty', 'Manager: after Empty the combination is an own EMPTY workflow, distinct from inheriting');

// Return to the generic workflow: scope and rules gone.
await Promise.all([t.page.waitForURL(/project_workflows/), transitionsCell.getByText('Return to the generic workflow').click()]);
await t.settle();
t.check('return to generic');
assert(t, scopes(P).length === 0, 'returning removes the decision');
assert(t, (await transitionsCell.textContent()).includes('Follows the generic workflow'), 'the cell follows the generic workflow again');

// Own empty workflow straight away, on field permissions.
const permCell = bugFull.locator('td.project-workflow-permissions');
await Promise.all([t.page.waitForURL(/project_workflows/), permCell.getByText('Give own empty workflow').click()]);
await t.settle();
assert(t, JSON.stringify(scopes(P)) === JSON.stringify([[BUG, FULL, 'permissions']]), 'give own empty workflow creates one permissions scope and no rules');
await t.shot('manager-perm-empty', 'Manager: field permissions given an own empty workflow directly');

// A forged request for a tracker that does not exist is refused, nothing written.
const forged = await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=999999&role_id=${FULL}&rule_type=transitions&source=copy`);
assert(t, forged === 404, `a scope request naming a tracker that does not exist answers 404 (got ${forged})`);
assert(t, scopes(P).length === 1, 'and writes nothing');

// --- viewer: reads, cannot change --------------------------------------------
await t.login('viewer');
await t.go(tab);
assert(t, await t.page.locator('table.project-workflow-settings').count() === 1, 'viewer sees the tab');
assert(t, await t.page.getByText('Give own workflow (copy of the generic one)').count() === 0, 'but is offered no action');
await t.shot('viewer-readonly', 'Viewer (view permission only): the tab is shown read-only, no actions');
const viewerPost = await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=copy`);
assert(t, viewerPost === 403, `a viewer posting the enable action directly gets 403 (got ${viewerPost})`);
assert(t, scopes(P).length === 1, 'and nothing is written');

// --- reporter: no plugin permission, no tab -----------------------------------
await t.login('reporter');
await t.go('/projects/e2e-project/settings', { status: 403 });
await t.shot('reporter-no-settings', 'Reporter (no plugin permission, no project settings): project settings refused');
await t.go(`/projects/e2e-project/workflow/transitions?tracker_id=${BUG}&role_id=${FULL}`, { status: 403 });
await t.shot('reporter-matrix-403', 'Reporter: the project matrix URL answers 403');

// --- outsider: the private project stays invisible ---------------------------
await t.login('outsider');
await t.go(`/projects/e2e-private/settings?tab=project_workflows`, { status: 403 });
await t.go(`/projects/e2e-private/workflow/transitions?tracker_id=${BUG}&role_id=${FULL}`, { status: 403 });
await t.shot('outsider-private-403', 'Outsider: the private project and its workflow are refused');

// --- admin: sees the tab on every project ------------------------------------
await t.login('admin');
await t.go('/projects/e2e-private/settings?tab=project_workflows');
assert(t, await t.page.locator('table.project-workflow-settings').count() === 1, 'admin sees the tab on the private project');
await t.shot('admin-private-tab', 'Admin: the Workflow tab of the private project');

await t.done();
