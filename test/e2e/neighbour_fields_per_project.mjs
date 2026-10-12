// Round 6 (Jan, 2026-10-12): redmine_itil_priority's Impact and Urgency on this
// plugin's own matrices, per project. The manager makes Impact read-only for
// the viewer's role in e2e-project only; the viewer cannot change it there,
// and still can in e2e-private, which follows the generic workflow. Also the
// comparison screen and the administration matrix, and the refusals.
// Runs where redmine_itil_priority is installed and registers its fields (see
// docs/REDMINE7-MIGRATION.md); says SKIP elsewhere.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, assert, forge, acceptDialogs } from './support.mjs';

const ids = reset();
const offered = rails(`puts RedmineProjectWorkflows::Services::PermissionFields.extra_names.to_json`);
if (!Array.isArray(offered) || !offered.includes('impact_id')) {
  console.log(`SKIP  no plugin offers impact_id on this host (${JSON.stringify(offered)})`);
  process.exit(0);
}
const P = ids.project, Q = ids.private, BUG = ids.trackers.Bug, VIEW = ids.roles['E2E workflow viewer'];
const NEW = ids.statuses.New;
const sel = `tracker_id=${BUG}&role_id=${VIEW}`;
// The viewer is also a member of e2e-private with the same role, so one user
// can be compared across the two projects; undone at the end.
const priv = rails(`v = User.find_by!(login: 'viewer'); r = Role.find(${VIEW}); q = Project.find(${Q})
  Member.create!(principal: v, project: q, roles: [r]) unless Member.exists?(user_id: v.id, project_id: q.id)
  q.enabled_module_names = q.enabled_module_names | ['itil_priority']
  i = Issue.find_by!(project_id: q.id, subject: 'E2E private issue'); i.update_columns(tracker_id: ${BUG}, status_id: ${NEW})
  p = Issue.find_by!(project_id: ${P}, subject: 'E2E assigned issue'); p.update_columns(status_id: ${NEW})
  puts [i.id, p.id].to_json`);
const [privateIssue, projectIssue] = priv;
const t = await e2e('neighbour_fields_per_project');

try {
  // Manager: take the field permissions over (copy) and make Impact read-only for New.
  await t.login('manager');
  acceptDialogs(t.page);
  const st = await forge(t, 'POST', `/projects/e2e-project/workflow/scope?${sel}&rule_type=permissions&source=copy`);
  assert(t, st === 302, `the manager gives e2e-project its own field permissions for Bug x E2E workflow viewer (HTTP ${st})`);
  await t.go(`/projects/e2e-project/workflow/permissions?${sel}`);
  const rows = await t.page.locator('#workflow_form td.name').allTextContents();
  assert(t, rows.some(r => /Impact/.test(r)) && rows.some(r => /Urgency/.test(r)), 'the project matrix has Impact and Urgency rows');
  await t.page.locator(`#workflow_form select[name="permissions[${NEW}][impact_id]"]`).selectOption('readonly');
  await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#workflow_form input[type=submit]').click()]);
  await t.settle();
  t.check('save');
  const stored = rails(`puts WorkflowPermission.where(field_name: 'impact_id', tracker_id: ${BUG}, role_id: ${VIEW}).pluck(:project_id, :old_status_id, :rule).to_json`);
  assert(t, JSON.stringify(stored) === JSON.stringify([[P, NEW, 'readonly']]), `Impact read-only for New is stored for e2e-project only (${JSON.stringify(stored)})`);
  await t.shot('project-matrix-saved', 'Manager: e2e-project own Fields permissions for Bug x E2E workflow viewer, with Impact and Urgency rows; Impact read-only for New saved');

  // Comparison: the difference is shown as a field the matrix offers.
  await t.go(`/projects/e2e-project/workflow/compare?${sel}&rule_type=permissions`);
  const cmp = await t.page.locator('#content').textContent();
  assert(t, /Impact/.test(cmp) && /Only in this project|Different/.test(cmp), 'the comparison lists Impact as a difference of this project');
  assert(t, await t.page.locator('p.project-workflow-comparison-note').count() === 0, 'and no longer notes a field the matrix cannot show');
  await t.shot('compare', 'Manager: the comparison names the Impact rule as only in this project');

  // The viewer, in e2e-project: Impact is read-only, no select.
  await t.login('viewer');
  await t.go(`/issues/${projectIssue}/edit`);
  assert(t, await t.page.locator('select#issue_impact_id').count() === 0, 'in e2e-project the viewer has no Impact select (read-only)');
  assert(t, await t.page.locator('select#issue_urgency_id').count() === 1, 'while Urgency stays editable');
  await t.shot('viewer-project-readonly', 'Viewer in e2e-project: Impact is read-only (no select), Urgency still editable');
  const forged = await forge(t, 'PATCH', `/issues/${projectIssue}`, { 'issue[impact_id]': '1' });
  const impactAfter = rails(`puts Issue.find(${projectIssue}).impact_id.to_json`);
  assert(t, impactAfter !== 1, `a forged change of Impact is ignored (HTTP ${forged}, impact_id ${impactAfter})`);

  // The viewer, in e2e-private: the generic workflow, Impact editable.
  await t.go(`/issues/${privateIssue}/edit`);
  assert(t, await t.page.locator('select#issue_impact_id').count() === 1, 'in e2e-private (generic workflow) the same viewer may change Impact');
  await t.shot('viewer-other-project-editable', 'Viewer in e2e-private: the generic workflow applies, Impact is editable');

  // Viewer cannot edit the matrix.
  const vs = await forge(t, 'PATCH', '/projects/e2e-project/workflow/permissions',
    { tracker_id: `${BUG}`, role_id: `${VIEW}`, [`permissions[${NEW}][impact_id]`]: '' });
  assert(t, vs === 403, `the viewer's forged matrix save answers 403 (HTTP ${vs})`);

  // Admin: the administration matrix offers the rows too.
  await t.login('admin');
  await t.go(`/project_workflow_rules/permissions?tracker_id[]=${BUG}&role_id[]=${VIEW}&project_id[]=${P}`);
  const adminRows = await t.page.locator('#content td.name').allTextContents();
  assert(t, adminRows.some(r => /Impact/.test(r)) && adminRows.some(r => /Urgency/.test(r)), 'the administration matrix has Impact and Urgency rows');
  assert(t, await t.page.locator(`select[name="permissions[${NEW}][impact_id]"]`).inputValue() === 'readonly', 'and shows e2e-project\'s read-only Impact');
  await t.shot('admin-matrix', 'Admin: Project workflows -> Fields permissions for e2e-project shows Impact (read-only for New) and Urgency');

  // Refusals.
  await t.login('reporter');
  await t.go(`/projects/e2e-project/workflow/permissions?${sel}`, { status: 403 });
  await t.login('outsider');
  await t.go(`/projects/e2e-project/workflow/permissions?${sel}`, { status: 403 });
  await t.go(`/project_workflow_rules/permissions?tracker_id[]=${BUG}&role_id[]=${VIEW}`, { status: 403 });
  await t.shot('outsider-403', 'Outsider: the project and administration Fields permissions answer 403 (reporter: 403 as well)');
} finally {
  rails(`v = User.find_by!(login: 'viewer'); Member.where(user_id: v.id, project_id: ${Q}).destroy_all`);
}
await t.done();
