// Shared by the plugin's scenarios in test/e2e/. Not a scenario itself: e2e.sh
// runs every *.mjs here, and this one only exports helpers, so running it does
// nothing.
//
// The scenarios drive the browser; this file reaches the same database through
// `rails runner` in the server's environment, for two things a browser cannot
// do: put the plugin back in its starting state, and read what a click wrote.
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const REDMINE_DIR = process.env.REDMINE_DIR || 'redmine';
const ENV = process.env.RMP_SERVER_ENV || 'production';

// Runs Ruby in the server's Rails environment and returns what it printed last,
// parsed as JSON when it is JSON.
export function rails(code) {
  const out = execFileSync('bundle', ['exec', 'rails', 'runner', code],
    { cwd: REDMINE_DIR, env: { ...process.env, RAILS_ENV: ENV }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const last = out.trim().split('\n').pop() || '';
  try { return JSON.parse(last); } catch { return last; }
}

// No project has a workflow of its own, the settings are the defaults, and the
// ids the scenarios need, by name.
export function reset() {
  return rails(`
    ProjectWorkflowScope.delete_all
    WorkflowRule.where.not(project_id: nil).delete_all
    Setting.plugin_redmine_project_workflows = Redmine::Plugin.find(:redmine_project_workflows).settings[:default]
    p = Project.find_by!(identifier: 'e2e-project')
    q = Project.find_by!(identifier: 'e2e-private')
    puts({ project: p.id, private: q.id,
           trackers: Tracker.order(:position).map { |t| [t.name, t.id] }.to_h,
           roles: Role.order(:position).map { |r| [r.name, r.id] }.to_h,
           statuses: IssueStatus.order(:position).map { |s| [s.name, s.id] }.to_h,
           issues: Issue.where(project_id: p.id).order(:id).map { |i| [i.subject, i.id] }.to_h }.to_json)
  `);
}

// Rules stored for one project (nil: the generic workflow), tracker and role.
export function ruleCount({ project = null, tracker, role, type = 'WorkflowTransition' }) {
  return rails(`puts ${type}.where(project_id: ${project === null ? 'nil' : project}, tracker_id: ${tracker}, role_id: ${role}).count`);
}

export function scopes(project) {
  return rails(`puts ProjectWorkflowScope.where(project_id: ${project}).map { |s| [s.tracker_id, s.role_id, s.rule_type] }.to_json`);
}

// Accept every confirm() the page raises, and count them.
export function acceptDialogs(page) {
  const seen = [];
  page.on('dialog', async d => { seen.push(d.message()); await d.accept(); });
  return seen;
}

export function assert(t, ok, what) {
  if (!ok) t.problems.push(`assertion failed: ${what}`);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`);
}

export const plugin = path.basename(process.cwd());

// A request the page's own forms would never send, with the session's CSRF token,
// so a refusal proves the server checks and not merely that the link was hidden.
export async function forge(t, method, urlPath, form) {
  const token = await t.page.locator('meta[name=csrf-token]').getAttribute('content');
  const res = await t.page.request.fetch(t.BASE + urlPath,
    { method, headers: { 'X-CSRF-Token': token || '' }, form, maxRedirects: 0 });
  return res.status();
}
