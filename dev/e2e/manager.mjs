import { BASE, browser, newPage, login, shot, check, results, exitCode } from './lib.mjs';

const b = await browser();
const page = await newPage(b);

// A project manager who is not an administrator. This is the only place in the
// plugin where a non-administrator writes workflow data.
await login(page, 'mgr', 'testpass1!');
check('the manager is not an administrator',
      (await page.$('a[href="/admin"]')) === null);

// --- INV-3, state 1: the project inherits ---------------------------------
await page.goto(`${BASE}/projects/alpha/settings?tab=project_workflows`, { waitUntil: 'domcontentloaded' });
check('the Workflow settings tab is there for a manager',
      (await page.$('table.project-workflow-settings')) !== null);
let text = await page.textContent('#tab-content-project_workflows, #content');
check('a project that has decided nothing is shown as inheriting',
      /inherit/i.test(text), text.slice(0, 200).replace(/\s+/g, ' '));
await shot(page, '10-settings-tab-inheriting');

// The row for Bug x Manager, and its three INV-3 actions.
const rowCount = await page.$$eval('table.project-workflow-settings tbody tr', r => r.length);
check('the tab lists one row per tracker and role the project can decide for',
      rowCount >= 3, `${rowCount} rows`);

// The actions are rails-ujs links with a data-confirm, so a real browser puts a
// dialog in the way. That path is never exercised by a request spec, which is
// exactly why it is worth driving here.
let dialogs = 0;
page.on('dialog', async d => { dialogs += 1; await d.accept(); });

const enable = page.locator('a', { hasText: 'Give own workflow (copy of the generic one)' }).first();
check('the tab offers "give own workflow"', await enable.count() > 0);
await Promise.all([page.waitForLoadState('domcontentloaded'), enable.click()]);
check('the browser asked for confirmation before taking the workflow over', dialogs === 1,
      `${dialogs} dialogs`);
text = await page.textContent('#content');
check('after enabling, the project is shown as running its own workflow',
      /own/i.test(text));
check('and the row now offers the two actions only an owner has',
      (await page.locator('a', { hasText: 'Return to the generic workflow' }).count()) > 0);
await shot(page, '11-settings-tab-own');

// --- editing the project's own matrix -------------------------------------
// Followed from the tab rather than by guessing ids. Redmine gives ids 1 and 2
// to Non-member and Anonymous, so role_id=1 is not a role this project offers --
// and the plugin answers 404 for it, correctly. A test that hardcoded it would
// have reported that refusal as a defect.
const matrixLink = page.locator('table.project-workflow-settings a[href*="/workflow/transitions"]').first();
check('the settings tab links each row into its matrix', await matrixLink.count() > 0);
await Promise.all([page.waitForLoadState('domcontentloaded'), matrixLink.click()]);
check('the project matrix renders', (await page.$('#workflow_form')) !== null, page.url());
const before = await page.$$eval('input[type=checkbox][name^="transitions"]:checked', e => e.length);
check('it opened with the generic rules copied in', before > 0, `${before} ticked`);

// Untick the first ticked box and save -- a real edit, through the real form.
// Rails renders a hidden input of the same name in front of every checkbox, so
// the checkbox has to be addressed as the checkbox and not by name alone.
const boxes = page.locator('input[type=checkbox][name^="transitions"]:checked');
const firstName = await boxes.first().getAttribute('name');
await boxes.first().uncheck();
await Promise.all([page.waitForLoadState('domcontentloaded'),
                   page.click('#workflow_form input[type=submit], #workflow_form button[type=submit]')]);
text = await page.textContent('#content');
check('the save reports success', /success|updated|bijgewerkt/i.test(text),
      text.slice(0, 200).replace(/\s+/g, ' '));
const after = await page.$$eval('input[type=checkbox][name^="transitions"]:checked', e => e.length);
check('the unticked rule is gone after the save', after === before - 1, `${before} -> ${after}`);
await shot(page, '12-project-matrix-after-save');

// --- the generic workflow is untouched (INV-1) ----------------------------
const alphaUrl = new URL(page.url());
await page.goto(`${BASE}/projects/beta/workflow/transitions${alphaUrl.search}`,
                { waitUntil: 'domcontentloaded' });
const betaText = await page.textContent('#content');
// The precise INV-1 check: the exact cell the manager just removed from alpha's
// own workflow is still there in the workflow beta inherits. A generic write
// would have taken it from both.
const readonlyName = firstName.replace('transitions[', 'readonly_transitions[');
const stillThere = await page.locator(`input[type=checkbox][name="${readonlyName}"]`).isChecked();
check('the rule alpha removed is untouched in the workflow beta inherits (INV-1)',
      stillThere, readonlyName);
check('beta is shown as following the generic workflow, read-only',
      /follows the generic workflow/i.test(betaText));
check('and its grid is the read-only one, not an editable form',
      (await page.locator('input[type=checkbox][name^="readonly_transitions"]').count()) > 0 &&
      (await page.locator('input[type=checkbox][name^="transitions"]').count()) === 0);
check('while still offering to take the workflow over',
      (await page.locator('a', { hasText: 'Give own workflow (copy of the generic one)' }).count()) > 0);
await shot(page, '13-beta-inherits');

console.log('\nerrors seen:', page.__errors.length);
page.__errors.forEach(e => console.log('   ', e));
check('no JavaScript error or failed request on the project screens',
      page.__errors.length === 0, page.__errors.join(' | '));

await b.close();
console.log(`\n${results.filter(r => r.ok).length}/${results.length} checks passed`);
process.exit(exitCode());
