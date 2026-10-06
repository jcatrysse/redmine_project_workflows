// Redmine's own Administration -> Workflow still edits the generic workflow,
// and only that (INV-1): with a project holding its own workflow, a generic
// save, a generic field-permission save and a generic copy leave the project's
// rows alone. The plugin adds the row/column Yes/No/undo actions to core's
// grid (Deface) and a link across to Project workflows; the summary counts the
// generic workflow only (INV-4).
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, ruleCount, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const P = ids.project, BUG = ids.trackers.Bug, FEATURE = ids.trackers.Feature, FULL = ids.roles['E2E full'];
const DEV = ids.roles.Developer;
// Restore the generic Bug x E2E full workflow at the end: copy of Manager.
const restore = () => rails(`WorkflowRule.where(project_id: nil, role_id: ${FULL}).delete_all
  r = Role.find(${FULL}); r.copy_workflow_rules(Role.find_by!(name: 'Manager'))
  WorkflowRule.where.not(project_id: nil).where(role_id: ${FULL}).delete_all; ProjectWorkflowScope.delete_all`);

const t = await e2e('core_workflow');
await t.login('admin');
acceptDialogs(t.page);
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=copy`);
const projectRules = ruleCount({ project: P, tracker: BUG, role: FULL });

// Summary: counts the generic workflow only.
await t.go('/workflows');
const cell = rails(`puts WorkflowTransition.where(project_id: nil, tracker_id: ${BUG}, role_id: ${FULL}).count`);
assert(t, (await t.page.locator('#content table').textContent()).includes(String(cell)), `the summary shows the generic count (${cell}) for Bug x E2E full`);
await t.shot('summary', "Admin: Redmine's own workflow summary counts the generic workflow only");

// Generic matrix: column action "No" on Resolved, save.
await t.go(`/workflows/edit?role_id[]=${FULL}&tracker_id[]=${BUG}`);
assert(t, await t.page.locator('a.project-workflow-bulk-action').count() > 0, "the plugin's Yes/No row and column actions are on core's grid");
const resolved = ids.statuses.Resolved;
const header = t.page.locator('table.transitions-always thead td, table.transitions-always thead th').filter({ hasText: 'Resolved' }).first();
await header.locator('a.project-workflow-bulk-action').getByText('No', { exact: true }).click();
const stillTicked = await t.page.locator(`table.transitions-always input.new-status-${resolved}:checked:not([disabled])`).count();
assert(t, stillTicked === 0, 'one click cleared the whole Resolved column');
// Recorded as finding M1 in docs/REDMINE7-MIGRATION.md: README promises "a count of
// what changed and an Undo" on every matrix, but core's own screen renders the
// actions without the counter (the undo region lives on the plugin's screens only).
// Same on 5.1; not a Redmine 7 regression. This line documents today's behaviour.
assert(t, await t.page.locator('#project-workflow-bulk-undo').count() === 0, "core's own screen has the actions but no change counter or Undo (finding M1)");
await t.shot('generic-column-no', "Admin: core's generic matrix, the Resolved column cleared with the plugin's column action (no counter here, finding M1)");
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#workflow_form input[type=submit]').click()]);
await t.settle();
t.check('generic save');
const toResolved = rails(`puts WorkflowTransition.where(project_id: nil, tracker_id: ${BUG}, role_id: ${FULL}, new_status_id: ${resolved}).count`);
assert(t, toResolved === 0, `the generic workflow lost every "to Resolved" rule (${toResolved} left)`);
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === projectRules, `the project's own ${projectRules} rules are untouched (INV-1)`);
await t.shot('generic-saved', "Admin: core's matrix after Save; the project's own workflow is not affected");

// Generic field permissions save.
await t.go(`/workflows/permissions?role_id[]=${FULL}&tracker_id[]=${BUG}`);
const sel = t.page.locator('select[name^="permissions"]:not([disabled])').first();
await sel.selectOption('readonly');
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#workflow_form input[type=submit]').click()]);
await t.settle();
assert(t, rails(`puts WorkflowPermission.where(project_id: nil, tracker_id: ${BUG}, role_id: ${FULL}).count`) === 1, 'the generic field permission was saved');
assert(t, rails(`puts WorkflowPermission.where.not(project_id: nil).count`) === 0, 'no project permission row was written');
await t.shot('generic-permissions', "Admin: core's field permissions saved for the generic workflow");

// Core's copy: generic Bug x E2E full onto Feature x Developer.
await t.go('/workflows/copy');
await t.page.locator('select[name=source_tracker_id]').selectOption(`${BUG}`);
await t.page.locator('select[name=source_role_id]').selectOption(`${FULL}`);
await t.page.locator('select[name="target_tracker_ids[]"]').selectOption([`${FEATURE}`]);
await t.page.locator('select[name="target_role_ids[]"]').selectOption([`${DEV}`]);
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#content input[type=submit]').click()]);
await t.settle();
t.check('core copy');
const devGeneric = ruleCount({ tracker: FEATURE, role: DEV });
assert(t, devGeneric === ruleCount({ tracker: BUG, role: FULL }), `core's copy wrote the generic rules (${devGeneric})`);
assert(t, ruleCount({ project: P, tracker: BUG, role: FULL }) === projectRules && ruleCount({ project: P, tracker: FEATURE, role: DEV }) === 0,
  'and wrote nothing for any project');
await t.shot('core-copy', "Admin: core's workflow copy, generic only");
// Put Developer's Feature workflow back from Manager's.
rails(`WorkflowRule.where(project_id: nil, tracker_id: ${FEATURE}, role_id: ${DEV}).delete_all
  WorkflowRule.where(project_id: nil, tracker_id: ${FEATURE}, role_id: Role.find_by!(name: 'Manager').id).each { |w| w.class.create!(w.attributes.except('id').merge('role_id' => ${DEV})) }`);

// Not for anybody else.
await t.login('manager');
await t.go('/workflows/edit', { status: 403 });
await t.shot('manager-403', "Manager: Redmine's own workflow administration answers 403");
restore();

await t.done();
