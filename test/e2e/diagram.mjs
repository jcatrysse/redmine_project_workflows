// The workflow diagram: drawn for one tracker and the roles chosen, as manager
// and viewer; refused for the reporter and the outsider; switched off by the
// plugin setting; folded away above the arrow ceiling; a role the project does
// not offer is refused.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, assert, forge } from './support.mjs';

const ids = reset();
const BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'], VIEW = ids.roles['E2E workflow viewer'];
const url = `/projects/e2e-project/workflow/graph?tracker_id=${BUG}&role_id[]=${FULL}`;
const t = await e2e('diagram');

await t.login('manager');
// Redmine's default workflow (every status to every other) is folded away as
// too dense to draw: the page says so and keeps the table.
await t.go(url);
assert(t, await t.page.locator('details.project-workflow-graph-disclosure').count() === 1, 'the everything-to-everything generic workflow is folded behind "Show the diagram anyway"');
await t.shot('dense-folded', 'Manager: the generic workflow permits nearly every move, so the drawing is folded away and the table is shown');

// An own workflow with a real path: New -> In Progress -> Resolved -> Closed,
// author-only Resolved -> In Progress, Rejected unreachable.
const S = ids.statuses;
await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=empty`);
// Fixture written directly (not a workflow write under test), so the drawing has a known shape.
rails(`[[${S.New}, ${S['In Progress']}, false, false], [${S['In Progress']}, ${S.Resolved}, false, false], [${S.Resolved}, ${S.Closed}, false, false], [${S.Resolved}, ${S['In Progress']}, true, false]].each do |o, n, a, b|
  WorkflowTransition.create!(project_id: ${ids.project}, tracker_id: ${BUG}, role_id: ${FULL}, old_status_id: o, new_status_id: n, author: a, assignee: b)
end`);
await t.go(url);
assert(t, await t.page.locator('details.project-workflow-graph-disclosure').count() === 0, 'a workflow with a path is drawn straight away');
const labels = await t.page.locator('#content svg text').allTextContents();
assert(t, ['New', 'In Progress', 'Resolved', 'Closed'].every(n => labels.some(l => l.includes(n))), `the drawing labels the statuses (${labels.slice(0, 8).join(', ')})`);
const diag = t.page.locator('ul.project-workflow-graph-diagnostics li');
assert(t, (await diag.filter({ hasText: 'Nothing leads out of these' }).textContent()).includes('Closed'), 'it lists Closed as a status nothing leads out of');
assert(t, (await diag.filter({ hasText: 'Not used by the selected roles' }).textContent()).includes('Rejected'), 'and Rejected as not used by the selected roles');
await t.shot('manager', 'Manager: own workflow drawn as a diagram with a dashed author-only arrow; Closed a dead end, Feedback and Rejected unused');

// Above the arrow ceiling the picture is not drawn, the table stays.
rails(`Setting.plugin_redmine_project_workflows = Setting.plugin_redmine_project_workflows.merge('graph_edge_ceiling' => '3')`);
await t.go(url);
const text = await t.page.locator('#content').textContent();
assert(t, /more than the 3 this installation draws/.test(text), 'above the arrow ceiling the page says it is not drawn');
assert(t, await t.page.locator('#content svg text').count() === 0, 'and draws nothing');
await t.shot('over-ceiling', 'Manager: with graph_edge_ceiling = 3 the 5-arrow workflow is not drawn; the table remains');

// Switched off: the screen is gone, and so is the link to it.
await t.go('/projects/e2e-project/settings/project_workflows');
assert(t, await t.page.locator('a.project-workflow-graph-link').count() > 0, 'while the diagram is on, the settings tab links to it');
rails(`Setting.plugin_redmine_project_workflows = Setting.plugin_redmine_project_workflows.merge('graph_edge_ceiling' => '2000', 'graph_enabled' => '0')`);
await t.go(url, { status: 404 });
await t.shot('disabled-404', 'Manager: with the diagram switched off in the plugin settings, the page answers 404');
await t.go('/projects/e2e-project/settings/project_workflows');
assert(t, await t.page.locator('a.project-workflow-graph-link').count() === 0, 'and the settings tab no longer offers it');
rails(`Setting.plugin_redmine_project_workflows = Setting.plugin_redmine_project_workflows.merge('graph_enabled' => '1')`);

// Invalid input: a role this project does not offer, a tracker that does not exist.
await t.go(`/projects/e2e-project/workflow/graph?tracker_id=${BUG}&role_id[]=${ids.roles.Developer}`, { status: 404 });
await t.go(`/projects/e2e-project/workflow/graph?tracker_id=999999&role_id[]=${FULL}`, { status: 404 });
await t.shot('bad-tracker-404', 'Manager: a tracker id that names nothing answers 404');

// Viewer: may read the diagram (view permission), for their own role too.
await t.login('viewer');
await t.go(`/projects/e2e-project/workflow/graph?tracker_id=${BUG}&role_id[]=${VIEW}`);
assert(t, await t.page.locator('#content svg').count() > 0, 'the viewer sees the diagram');
await t.shot('viewer', 'Viewer: the diagram for their own role');

await t.login('reporter');
await t.go(url, { status: 403 });
await t.shot('reporter-403', 'Reporter (no plugin permission): the diagram answers 403');
await t.login('outsider');
await t.go(`/projects/e2e-private/workflow/graph?tracker_id=${BUG}&role_id[]=${FULL}`, { status: 403 });

await t.done();
