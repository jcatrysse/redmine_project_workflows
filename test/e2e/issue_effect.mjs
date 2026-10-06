// What the plugin is for: the status a user may pick on a real issue follows the
// project's own workflow. Through the three states (inherits, own empty, own
// with one rule), on the issue form, in the "Workflow for this issue" panel, in
// the REST API (include=allowed_statuses), and in a Redmine 7 webhook.
import http from 'node:http';
import os from 'node:os';
import { e2e } from '../../.codex/e2e/lib.mjs';
import { reset, rails, acceptDialogs, assert, forge } from './support.mjs';

const ids = reset();
const BUG = ids.trackers.Bug, FULL = ids.roles['E2E full'];
const S = ids.statuses;
const issue = ids.issues['E2E assigned issue'];
const PASSWORD = process.env.RMP_USER_PASSWORD || 'Redmine7Test!';
// The issue starts every run in New.
rails(`i = Issue.find(${issue}); i.update_columns(status_id: ${S.New}, closed_on: nil)`);

const t = await e2e('issue_effect');
const options = async () => t.page.locator('#issue_status_id option').allTextContents();
const apiStatuses = async (login) => {
  const auth = 'Basic ' + Buffer.from(`${login}:${PASSWORD}`).toString('base64');
  const r = await t.page.request.get(`${t.BASE}/issues/${issue}.json?include=allowed_statuses`, { headers: { Authorization: auth } });
  return (await r.json()).issue.allowed_statuses.map(s => s.name);
};
async function openPanel(name, caption) {
  await t.page.locator('a.project-workflow-map-link').first().click();
  await t.page.locator('#ajax-modal .project-workflow-map').waitFor();
  const text = await t.page.locator('#ajax-modal').textContent();
  await t.shot(name, caption);
  await t.page.keyboard.press('Escape');
  return text;
}

// 1. Inheriting.
await t.login('manager');
acceptDialogs(t.page);
await t.go(`/issues/${issue}/edit`);
const inherited = await options();
assert(t, inherited.length > 2, `while the project inherits, the status list offers ${inherited.join(', ')}`);
const panel1 = await openPanel('panel-inherits', 'Manager: "Workflow for this issue" says the project follows the generic workflow');
assert(t, panel1.includes('Follows the generic workflow'), 'the panel names the generic workflow');
const api1 = await apiStatuses('manager');
assert(t, api1.length === inherited.length, `REST include=allowed_statuses agrees with the form (${api1.join(', ')})`);

// 2. Own EMPTY workflow for Bug x E2E full: no status change at all.
let st = await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=empty`);
assert(t, st === 302, `give own empty workflow (HTTP ${st})`);
await t.go(`/issues/${issue}/edit`);
assert(t, await t.page.locator('#issue_status_id').count() === 0, 'with an own empty workflow Redmine drops the status field');
assert(t, await t.page.locator('a.project-workflow-map-link').count() > 0, 'and the panel link is still there to say why');
const panel2 = await openPanel('panel-own-empty', 'Manager: own EMPTY workflow, no status field; the panel says why');
assert(t, /Own empty workflow/.test(panel2), 'the panel names the own empty workflow');
const api2 = await apiStatuses('manager');
assert(t, api2.length === 0, `REST allowed_statuses is empty (${JSON.stringify(api2)})`);

// 3. Own workflow with exactly one rule: New -> In Progress.
st = await forge(t, 'POST', `/projects/e2e-project/workflow/scope/clear?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions`);
st = await forge(t, 'DELETE', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions`);
st = await forge(t, 'POST', `/projects/e2e-project/workflow/scope?tracker_id=${BUG}&role_id=${FULL}&rule_type=transitions&source=copy`);
// The form sends every cell (a hidden 0 before each checkbox); a cell left out
// of the request is "no change" to the plugin, so send them all, as the form does.
const cells = { tracker_id: `${BUG}`, role_id: `${FULL}` };
for (const from of [0, ...Object.values(S)]) {
  for (const to of Object.values(S)) cells[`transitions[${from}][${to}][always]`] = '0';
}
cells[`transitions[${S.New}][${S['In Progress']}][always]`] = '1';
st = await forge(t, 'PATCH', '/projects/e2e-project/workflow/transitions', cells);
const own = rails(`puts WorkflowTransition.where(project_id: ${ids.project}, tracker_id: ${BUG}, role_id: ${FULL}).pluck(:old_status_id, :new_status_id).to_json`);
assert(t, JSON.stringify(own) === JSON.stringify([[S.New, S['In Progress']]]), `the project now holds exactly New -> In Progress (${JSON.stringify(own)})`);
await t.go(`/issues/${issue}/edit`);
const narrowed = await options();
assert(t, JSON.stringify(narrowed) === JSON.stringify(['New', 'In Progress']), `the status list offers only ${narrowed.join(', ')}`);
await t.shot('form-own-one-rule', 'Manager: own workflow with one rule, the status list offers New and In Progress only');
const panel3 = await openPanel('panel-own', 'Manager: the panel lists the one permitted change');
assert(t, panel3.includes('In Progress') && panel3.includes('Own workflow'), 'the panel shows the own workflow and its one change');
assert(t, JSON.stringify(await apiStatuses('manager')) === JSON.stringify(['New', 'In Progress']), 'REST allowed_statuses agrees');

// 4. The viewer holds another role: the generic workflow still applies to them.
await t.login('viewer');
await t.go(`/issues/${issue}/edit`);
const other = await options();
assert(t, JSON.stringify(other) === JSON.stringify(inherited), `the viewer's list is still the generic one for their role (${other.join(', ')})`);
await t.shot('viewer-generic', 'Viewer (role E2E workflow viewer): the project workflow for E2E full does not narrow another role');

// 5. A webhook (new in Redmine 7) carries the change; the plugin adds nothing to it.
const received = [];
// Redmine 7 refuses loopback webhook targets, so the listener takes the
// container's own address.
const ip = Object.values(os.networkInterfaces()).flat().find(a => a.family === 'IPv4' && !a.internal).address;
const hookUrl = `http://${ip}:3901/hook`;
const server = http.createServer((req, res) => {
  let body = ''; req.on('data', c => { body += c; });
  req.on('end', () => { received.push(JSON.parse(body)); res.end('ok'); });
}).listen(3901, ip);
rails(`Setting.webhooks_enabled = '1'
  Webhook.where(url: '${hookUrl}').destroy_all
  User.current = User.find_by(login: 'manager')
  Webhook.create!(url: '${hookUrl}', user: User.current, events: ['issue.updated'], active: true,
                  projects: [Project.find(${ids.project})])`);
await t.login('manager');
await t.go(`/issues/${issue}/edit`);
await t.page.locator('#issue_status_id').selectOption({ label: 'In Progress' });
await Promise.all([t.page.waitForLoadState('load'), t.page.locator('#issue-form input[name=commit]').click()]);
await t.settle();
t.check('status change');
assert(t, (await t.page.locator('.issue .status').first().textContent()).includes('In Progress'), 'the manager moved the issue to In Progress');
await t.shot('status-changed', 'Manager: the issue moved New -> In Progress under the project workflow');
for (let i = 0; i < 40 && received.length === 0; i++) await new Promise(r => setTimeout(r, 250));
server.close();
assert(t, received.length === 1, `the webhook was delivered (${received.length})`);
const hook = received[0] || { data: { issue: {} } };
assert(t, hook.type === 'issue.updated' && hook.data.issue.status?.name === 'In Progress', `its payload carries the new status (${hook.type}, ${hook.data.issue.status?.name})`);
assert(t, !('allowed_statuses' in hook.data.issue), 'and no allowed_statuses: the workflow is not part of the payload');
// Now in In Progress the own workflow permits nothing further.
await t.go(`/issues/${issue}/edit`);
assert(t, await t.page.locator('#issue_status_id').count() === 0, 'from In Progress the own workflow permits nothing, so no status field');
rails(`Webhook.where(url: '${hookUrl}').destroy_all; Setting.webhooks_enabled = '0'`);

// 6. Outsider: the private project's panel is not reachable.
const priv = rails(`puts Issue.find_by(subject: 'E2E private issue').id`);
await t.login('outsider');
await t.go(`/issues/${priv}/workflow_map?tracker_id=${BUG}`, { status: 404 });
await t.shot('outsider-panel-404', 'Outsider: the panel of an issue in the private project answers 404');
await t.go(`/projects/e2e-private/workflow_map?tracker_id=${BUG}`, { status: 403 });

await t.done();
