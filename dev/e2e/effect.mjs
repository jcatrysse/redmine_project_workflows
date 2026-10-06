import { BASE, browser, newPage, login, shot, check, results, exitCode } from './lib.mjs';

const b = await browser();
const page = await newPage(b);
page.on('dialog', async d => await d.accept());

// What all of this is FOR: the status dropdown on an issue.
// gamma gets an own EMPTY workflow -- INV-3's third state, the one that is a
// decision rather than an absence -- and the effect has to be visible on a real
// issue form, not only in the matrix.

await login(page, 'mgr', 'testpass1!');

// 1. Baseline: on gamma, which inherits, an issue can move somewhere.
await page.goto(`${BASE}/projects/gamma/issues/new`, { waitUntil: 'domcontentloaded' });
check('a manager can open the new-issue form on gamma', (await page.$('#issue_subject')) !== null);
await page.fill('#issue_subject', 'A test issue for the workflow');
await Promise.all([page.waitForLoadState('domcontentloaded'),
                   page.click('input[type=submit][name=commit]')]);
const issueUrl = page.url();
check('the issue was created', /\/issues\/\d+/.test(issueUrl), issueUrl);

await page.goto(issueUrl + '/edit', { waitUntil: 'domcontentloaded' });
const before = await page.$$eval('#issue_status_id option', o => o.map(x => x.textContent.trim()));
check('while gamma inherits, the status dropdown offers more than the current status',
      before.length > 1, before.join(', '));
await shot(page, '20-issue-inheriting');

// 2. Give gamma an own EMPTY workflow for this tracker and the manager's role.
await page.goto(`${BASE}/projects/gamma/settings?tab=project_workflows`, { waitUntil: 'domcontentloaded' });
const empty = page.locator('table.project-workflow-settings a', { hasText: 'Give own empty workflow' }).first();
check('the tab offers "give own empty workflow"', await empty.count() > 0);
await Promise.all([page.waitForLoadState('domcontentloaded'), empty.click()]);
const tabText = await page.textContent('#content');
check('the tab distinguishes an own EMPTY workflow from inheriting (INV-3)',
      /empty/i.test(tabText), tabText.match(/[^.]*empty[^.]*/i)?.[0]?.trim()?.slice(0, 120));
await shot(page, '21-settings-tab-own-empty');

// 3. The effect on the issue: nothing is permitted any more.
await page.goto(issueUrl + '/edit', { waitUntil: 'domcontentloaded' });
const after = await page.$$eval('#issue_status_id option', o => o.map(x => x.textContent.trim()));
// Zero, not one. Redmine's own _attributes.html.erb renders the status field
// only `if @allowed_statuses.present?`, and core's new_statuses_allowed_to adds
// the current status only when something else is allowed -- so "no transition
// permitted" is a form with no status field at all. That is core's rendering of
// the state, not something the plugin draws.
check('an own EMPTY workflow permits no status change at all (INV-3)',
      after.length === 0, `before: ${before.join(', ')} | after: ${after.length} options`);
check('and Redmine drops the status field entirely rather than showing a dead one',
      (await page.locator('#issue_status_id').count()) === 0);
await shot(page, '22-issue-own-empty');

// 4. And giving it back restores the generic workflow.
await page.goto(`${BASE}/projects/gamma/settings?tab=project_workflows`, { waitUntil: 'domcontentloaded' });
await Promise.all([page.waitForLoadState('domcontentloaded'),
  page.locator('table.project-workflow-settings a', { hasText: 'Return to the generic workflow' }).first().click()]);
await page.goto(issueUrl + '/edit', { waitUntil: 'domcontentloaded' });
const restored = await page.$$eval('#issue_status_id option', o => o.map(x => x.textContent.trim()));
check('returning to the generic workflow restores what it permits',
      restored.length === before.length, restored.join(', '));

console.log('\nerrors seen:', page.__errors.length);
page.__errors.forEach(e => console.log('   ', e));
check('no JavaScript error or failed request on the issue screens',
      page.__errors.length === 0, page.__errors.join(' | '));

await b.close();
console.log(`\n${results.filter(r => r.ok).length}/${results.length} checks passed`);
process.exit(exitCode());
