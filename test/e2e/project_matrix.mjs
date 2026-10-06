// A project's own matrices: status transitions and field permissions, edited and
// saved by the manager, read-only for an inheriting combination and for the
// viewer; and the generic workflow left untouched by a project save (INV-1).
// Also the selection a request cannot widen: a tracker the project does not
// use, a role nobody holds there, another project's id.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, ruleCount, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const P = ids.project, BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'];
const sel = `tracker_id=${BUG}&role_id=${FULL}`;
const t = await e2e('project_matrix');

await t.login('manager');
acceptDialogs(t.page);

// Inheriting: read-only, shows the generic grid, offers to take it over.
await t.go(`/projects/e2e-project/workflow/transitions?${sel}`);
assert(t, await t.page.locator('#workflow_form').count() === 0, 'an inheriting combination has no editable form');
assert(t, await t.page.locator('input[name^="readonly_transitions"]:checked').count() > 0, 'it shows the generic rules read-only');
await t.shot('inherits-readonly', 'Manager: Bug x E2E full follows the generic workflow, so the matrix is read-only and shows the generic rules');

// Take it over from the matrix page itself.
await Promise.all([t.page.waitForLoadState('load'), t.page.getByText('Give own workflow (copy of the generic one)').first().click()]);
await t.settle();
t.check('enable from matrix');
assert(t, await t.page.locator('#workflow_form').count() === 1, 'after taking it over the matrix is editable');
const genericBefore = ruleCount({ tracker: BUG, role: FULL });
const ownBefore = ruleCount({ project: P, tracker: BUG, role: FULL });

// Untick one, tick one, save.
const firstTicked = t.page.locator('#workflow_form input[type=checkbox][name^="transitions"]:checked:not([disabled])').first();
const removed = await firstTicked.getAttribute('name');
await firstTicked.uncheck();
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#workflow_form input[type=submit]').click()]);
await t.settle();
t.check('save transitions');
assert(t, /Successful update/i.test(await t.page.locator('#flash_notice').textContent().catch(() => '')), 'the save reports "Successful update"');
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === ownBefore - 1, `the project now holds one rule fewer (${ownBefore} -> ${ownBefore - 1})`);
assert(t, ruleCount({ tracker: BUG, role: FULL }) === genericBefore, 'the generic workflow is untouched (INV-1)');
assert(t, !(await t.page.locator(`#workflow_form input[type=checkbox][name="${removed}"]`).isChecked()), 'the unticked rule stays unticked after reload');
await t.shot('own-saved', 'Manager: own transitions matrix after Save, one rule removed, "Successful update"');

// Field permissions: take over, make a field read-only, save.
await t.go(`/projects/e2e-project/workflow/permissions?${sel}`);
await t.shot('permissions-inherits', 'Manager: field permissions follow the generic workflow, read-only');
await Promise.all([t.page.waitForLoadState('load'), t.page.getByText('Give own workflow (copy of the generic one)').first().click()]);
await t.settle();
const select = t.page.locator('#workflow_form select[name^="permissions"]:not([disabled])').first();
const selName = await select.getAttribute('name');
await select.selectOption('readonly');
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#workflow_form input[type=submit]').click()]);
await t.settle();
t.check('save permissions');
const m = selName.match(/permissions\[(\d+)\]\[([^\]]+)\]/);
const stored = rails(`puts WorkflowPermission.where(project_id: ${P}, tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: ${m[1]}, field_name: '${m[2]}').pluck(:rule).to_json`);
assert(t, JSON.stringify(stored) === '["readonly"]', `the field ${m[2]} is stored read-only for this project only (${JSON.stringify(stored)})`);
assert(t, ruleCount({ tracker: BUG, role: FULL, type: 'WorkflowPermission' }) === 0 ||
  rails(`puts WorkflowPermission.where(project_id: nil, tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: ${m[1]}, field_name: '${m[2]}').count`) === 0,
  'and not in the generic workflow');
await t.shot('permissions-saved', `Manager: own field permissions saved, ${m[2]} read-only`);

// Compare with the generic workflow.
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('a', { hasText: 'Compare with the generic workflow' }).first().click()]);
await t.settle();
t.check('compare');
assert(t, /Only in the generic workflow|Different|Only in this project/.test(await t.page.locator('#content').textContent()), 'the comparison names the difference');
await t.shot('compare-permissions', 'Manager: comparison of own field permissions with the generic workflow');
await t.go(`/projects/e2e-project/workflow/compare?${sel}&rule_type=transitions`);
assert(t, (await t.page.locator('#content').textContent()).includes('Only in the generic workflow'), 'the removed transition is listed as only in the generic workflow');
await t.shot('compare-transitions', 'Manager: the transition removed above is "Only in the generic workflow"');

// Invalid selections: refused before anything is read or written.
await t.go(`/projects/e2e-project/workflow/transitions?tracker_id=999999&role_id=${FULL}`, { status: 404 });
await t.shot('invalid-tracker', 'Manager: a tracker id that names nothing answers 404');
await t.go(`/projects/e2e-project/workflow/transitions?tracker_id=${BUG}&role_id=${ids.roles.Developer}`, { status: 404 });
await t.go(`/projects/e2e-project/workflow/compare?${sel}&rule_type=bogus`, { status: 404 });
const before = ruleCount({ project: P, tracker: BUG, role: FULL });
const status = await forge(t, 'PATCH', `/projects/e2e-project/workflow/transitions`,
  { tracker_id: `${BUG}`, role_id: `${ids.roles.Developer}`, [`transitions[${ids.statuses.New}][${ids.statuses['In Progress']}][always]`]: '1' });
assert(t, status === 404, `a save for a role nobody holds in the project answers 404 (got ${status})`);
const bad = await forge(t, 'PATCH', `/projects/e2e-project/workflow/transitions`,
  { tracker_id: `${BUG}`, role_id: `${FULL}`, 'transitions[999999][1][always]': '1' });
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === before &&
  rails(`puts WorkflowTransition.where(project_id: ${P}, old_status_id: 999999).count`) === 0,
  `a save naming a status that does not exist changes nothing (HTTP ${bad}, ${before} rules before and after)`);
await t.go(`/projects/e2e-project/workflow/transitions?${sel}`);
const flash = (await t.page.locator('#flash_warning, #flash_error').allTextContents()).join(' ');
assert(t, /not accepted/.test(flash), `and the screen says the value was not accepted: "${flash.trim()}"`);
assert(t, await t.page.locator('#flash_notice').count() === 0, 'and does not claim success');
await t.shot('invalid-status-refused', 'Manager: after a forged save naming a status that does not exist, the screen says what happened and the matrix is unchanged');

// Viewer: read-only, even for an own workflow; a forged save is refused.
await t.login('viewer');
await t.go(`/projects/e2e-project/workflow/transitions?${sel}`);
assert(t, await t.page.locator('#workflow_form').count() === 0, 'the viewer gets no form on an own workflow');
await t.shot('viewer-own-readonly', 'Viewer: the own workflow is shown read-only, no Save, no actions');
const vs = await forge(t, 'PATCH', `/projects/e2e-project/workflow/transitions`, { tracker_id: `${BUG}`, role_id: `${FULL}` });
assert(t, vs === 403, `a viewer's forged save answers 403 (got ${vs})`);
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === ownBefore - 1, 'and the project rules are unchanged');

await t.login('reporter');
await t.go(`/projects/e2e-project/workflow/permissions?${sel}`, { status: 403 });
await t.shot('reporter-403', 'Reporter (no plugin permission): the permissions matrix answers 403');

await t.done();
