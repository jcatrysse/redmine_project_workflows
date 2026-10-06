import { BASE, browser, newPage, login, shot, check, results, exitCode } from './lib.mjs';

const b = await browser();
const page = await newPage(b);
page.on('dialog', async d => await d.accept());
await login(page, 'admin', 'adminadmin1!');

// --- the inventory ---------------------------------------------------------
await page.goto(`${BASE}/project_workflow_inventories`, { waitUntil: 'domcontentloaded' });
check('the inventory renders a table', (await page.locator('table.list').count()) > 0);
// Name-agnostic on purpose: the seed's project names are not what is under
// test, and an assertion on one of them fails the moment somebody renames it.
const rows = await page.locator('table.list tbody tr').count();
check('and it lists the project that has taken a workflow over', rows > 0, `${rows} rows`);
await shot(page, '50-inventory');

// --- the copy screen -------------------------------------------------------
await page.goto(`${BASE}/project_workflow_rules/copy`, { waitUntil: 'domcontentloaded' });
check('the copy screen renders its six selectors',
      (await page.locator('select, input[type=checkbox]').count()) >= 6);
await shot(page, '51-copy');

// A copy that names a target that does not exist must be refused, not written.
await page.evaluate(() => {
  const f = document.querySelector('form[action="/project_workflow_rules/duplicate"]');
  const add = (n, v) => { const i = document.createElement('input'); i.type='hidden'; i.name=n; i.value=v; f.appendChild(i); };
  add('target_tracker_ids[]', '999999');
});
const dupForm = page.locator('form[action="/project_workflow_rules/duplicate"]');
if (await dupForm.count()) {
  await Promise.all([page.waitForLoadState('domcontentloaded'),
                     dupForm.locator('input[type=submit]').first().click()]);
  const t = await page.textContent('#content');
  check('a copy naming a tracker that does not exist is refused with a message',
        /select|choose|invalid|does not|niet/i.test(t), t.replace(/\s+/g,' ').slice(0, 160));
}

// --- the comparison screen -------------------------------------------------
// Reached by its own link rather than a hand-built URL: the action needs a
// rule_type, and without one it answers 404 -- correctly, since a comparison of
// nothing in particular is not a page. A first attempt here omitted it and read
// that refusal as a defect.
await page.goto(`${BASE}/projects/alpha/workflow/transitions?tracker_id=1&role_id=3`,
                { waitUntil: 'domcontentloaded' });
const compareLink = page.locator('a.project-workflow-compare-link').first();
check('a project with its own workflow is offered the comparison',
      await compareLink.count() > 0);
await Promise.all([page.waitForLoadState('domcontentloaded'), compareLink.click()]);
check('the comparison screen renders', (await page.locator('table').count()) > 0, page.url());
const cmp = await page.textContent('#content');
check('and it names what the project changed',
      /only|generic|both|difference/i.test(cmp), cmp.replace(/\s+/g,' ').slice(0, 160));
await shot(page, '52-compare');

// --- the drawing -----------------------------------------------------------
await page.goto(`${BASE}/projects/alpha/workflow/graph?tracker_id=1&role_id[]=3`,
                { waitUntil: 'domcontentloaded' });
const svg = await page.locator('svg').count();
check('the workflow drawing renders an SVG', svg > 0, `${svg} svg elements`);
const nodes = await page.locator('svg text').count();
check('and the drawing has labelled statuses', nodes > 0, `${nodes} labels`);
await shot(page, '53-graph');

// --- the bulk row/column actions, which are this plugin's only JavaScript ---
await page.goto(`${BASE}/project_workflow_rules/edit?tracker_id[]=1&role_id[]=3`,
                { waitUntil: 'domcontentloaded' });
const before = await page.locator('input[type=checkbox][name^="transitions"]:checked').count();
const rowLinks = page.locator('a.project-workflow-bulk, [data-project-workflow-bulk], a[href="#"]');
const bulkCount = await page.locator('[class*="bulk"], [data-bulk]').count();
check('the matrix carries the bulk row/column controls', bulkCount > 0, `${bulkCount} controls`);
await shot(page, '54-admin-matrix-bulk');

console.log('\nerrors seen:', page.__errors.length);
page.__errors.forEach(e => console.log('   ', e));
check('no JavaScript error or failed request across these screens',
      page.__errors.length === 0, page.__errors.join(' | '));

await b.close();
console.log(`\n${results.filter(r => r.ok).length}/${results.length} checks passed`);
process.exit(exitCode());
