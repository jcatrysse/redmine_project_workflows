// Copying workflows: Administration -> Project workflows -> Copy (one source
// workflow onto several target projects), its refusals, and Redmine's own
// "Copy project", which carries the project's workflow decisions across when
// "Project workflows (N)" stays ticked and leaves them behind when it is not.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, ruleCount, scopes, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const P = ids.project, Q = ids.private, BUG = ids.trackers.Bug, FEATURE = ids.trackers.Feature, FULL = ids.roles['E2E full'];
rails(`Project.where(identifier: %w[e2e-copy-with e2e-copy-without]).each(&:destroy)`);
const t = await e2e('copy_workflows');
await t.login('admin');
acceptDialogs(t.page);

// Source: e2e-project gets an own workflow for Bug x E2E full with one rule.
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=empty`);
// Fixture written directly: the one rule the copy is expected to carry.
rails(`WorkflowTransition.create!(project_id: ${P}, tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: ${ids.statuses.New}, new_status_id: ${ids.statuses.Resolved})`);

// Copy screen: from e2e-project Bug x E2E full to e2e-private Feature x E2E full.
await t.go('/project_workflow_rules/copy');
await t.shot('copy-screen', 'Admin: the Copy screen (source tracker, role, project; target trackers, roles, projects)');
const form = t.page.locator('#workflow_copy_form');
await form.locator('select[name=source_tracker_id]').selectOption(`${BUG}`);
await form.locator('select[name=source_role_id]').selectOption(`${FULL}`);
await form.locator('select[name=source_project_id]').selectOption(`${P}`);
await form.locator('select[name="target_tracker_ids[]"]').selectOption([`${FEATURE}`]);
await form.locator('select[name="target_role_ids[]"]').selectOption([`${FULL}`]);
await form.locator('select[name="target_project_ids[]"]').selectOption([`${Q}`]);
await t.shot('copy-filled', 'Admin: copy e2e-project Bug x E2E full onto e2e-private Feature x E2E full');
await Promise.all([t.page.waitForLoadState('load'), form.locator('input[type=submit]').click()]);
await t.settle();
t.check('copy');
const copied = rails(`puts WorkflowTransition.where(project_id: ${Q}, tracker_id: ${FEATURE}, role_id: ${FULL}).pluck(:old_status_id, :new_status_id).to_json`);
assert(t, JSON.stringify(copied) === JSON.stringify([[ids.statuses.New, ids.statuses.Resolved]]), `the target holds exactly the source's one rule (${JSON.stringify(copied)})`);
assert(t, JSON.stringify(scopes(Q)) === JSON.stringify([[FEATURE, FULL, 'transitions']]), 'and has an own workflow (scope) for it');
assert(t, ruleCount({ tracker: FEATURE, role: FULL }) > 1, 'the generic Feature workflow is untouched');
await t.shot('copy-done', 'Admin: after Copy, the success message; e2e-private Feature x E2E full holds the copied rule');

// Refusals: no target, and a target that does not exist.
await t.go('/project_workflow_rules/copy');
await form.locator('select[name=source_tracker_id]').selectOption(`${BUG}`);
await form.locator('select[name=source_role_id]').selectOption(`${FULL}`);
await Promise.all([t.page.waitForLoadState('load'), form.locator('input[type=submit]').click()]);
await t.settle();
const msg = await t.page.locator('#flash_error, #errorExplanation, .flash.error').first().textContent().catch(() => '');
assert(t, msg.trim().length > 0, `a copy with no target is refused with a message ("${msg.trim().slice(0, 80)}")`);
await t.shot('copy-no-target', 'Admin: a copy without a target tracker or role is refused with a message');
const before = rails(`puts WorkflowRule.count`);
const st = await forge(t, 'POST', '/project_workflow_rules/duplicate',
  { source_tracker_id: `${BUG}`, source_role_id: `${FULL}`, 'target_tracker_ids[]': '999999', 'target_role_ids[]': `${FULL}` });
assert(t, rails(`puts WorkflowRule.count`) === before, `a copy to a tracker that does not exist writes nothing (HTTP ${st})`);

// Redmine's own Copy project, with and without the plugin's item.
for (const [ident, keep] of [['e2e-copy-with', true], ['e2e-copy-without', false]]) {
  await t.go(`/projects/e2e-private/copy`);
  const item = t.page.locator('label', { hasText: 'Project workflows' }).locator('input[type=checkbox]');
  assert(t, await item.count() === 1, 'Copy project offers "Project workflows (N)"');
  if (keep) {
    assert(t, /Project workflows \(1\)/.test(await t.page.locator('label', { hasText: 'Project workflows' }).textContent()), 'and counts the one decision it will bring');
    await t.shot('project-copy-form', 'Admin: Copy project lists "Project workflows (1)", ticked by default');
  } else {
    await item.uncheck();
  }
  await t.page.fill('#project_name', `E2E copy ${keep ? 'with' : 'without'}`);
  await t.page.fill('#project_identifier', ident);
  await Promise.all([t.page.waitForLoadState('load'), t.page.locator('input[name=commit]').first().click()]);
  await t.settle();
  t.check(`project copy ${ident}`);
  const id = rails(`puts Project.find_by(identifier: '${ident}')&.id.to_i`);
  assert(t, id > 0, `the project ${ident} was created`);
  const n = rails(`puts ProjectWorkflowScope.where(project_id: ${id}).count`);
  assert(t, n === (keep ? 1 : 0), `${ident}: ${n} workflow decision(s) copied`);
}
await t.go(`/projects/e2e-copy-with/settings/project_workflows`);
await t.shot('project-copy-result', 'Admin: the copied project has the own workflow for Feature x E2E full');
rails(`Project.where(identifier: %w[e2e-copy-with e2e-copy-without]).each(&:destroy)`);

// Manager: no access to the administration copy.
await t.login('manager');
await t.go('/project_workflow_rules/copy', { status: 403 });
const ms = await forge(t, 'POST', '/project_workflow_rules/duplicate',
  { source_tracker_id: `${BUG}`, source_role_id: `${FULL}`, 'target_tracker_ids[]': `${FEATURE}`, 'target_role_ids[]': `${FULL}` });
assert(t, ms === 403, `a manager's forged copy answers 403 (HTTP ${ms})`);
await t.shot('manager-403', 'Manager: the Copy screen answers 403');

await t.done();
