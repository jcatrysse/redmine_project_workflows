import { BASE, browser, newPage, login, shot, check, results, exitCode } from './lib.mjs';

const b = await browser();
const page = await newPage(b);

// --- scenario 1: an administrator finds the plugin -------------------------
await login(page, 'admin', 'adminadmin1!');
await page.goto(`${BASE}/admin`, { waitUntil: 'domcontentloaded' });
const adminLinks = await page.$$eval('#admin-menu a, a', as => as.map(a => a.getAttribute('href')));
check('admin menu carries exactly one plugin entry',
      adminLinks.filter(h => h === '/project_workflow_rules').length === 1,
      `project_workflow_rules links: ${adminLinks.filter(h => h === '/project_workflow_rules').length}`);
check('admin menu carries NO diagnostics entry (F07)',
      !adminLinks.includes('/project_workflow_diagnostics'));
await shot(page, '01-admin-menu');

// --- scenario 2: the summary screen ---------------------------------------
await page.goto(`${BASE}/project_workflow_rules`, { waitUntil: 'domcontentloaded' });
check('summary renders', (await page.title()).length > 0 && (await page.$('table.list')) !== null);
const ctx = await page.$$eval('div.contextual a', as => as.map(a => a.getAttribute('href')));
check('summary action bar links to diagnostics (F07)', ctx.includes('/project_workflow_diagnostics'),
      ctx.join(' '));
check('summary action bar links to the inventory', ctx.includes('/project_workflow_inventories'));
await shot(page, '02-summary');

// --- scenario 3: the diagnostics page and the way back --------------------
await page.goto(`${BASE}/project_workflow_diagnostics`, { waitUntil: 'domcontentloaded' });
const body = await page.textContent('body');
check('diagnostics page renders its compatibility state',
      /Redmine 5\.1/.test(body));
const back = await page.$$eval('h2 a, #content h2 a', as => as.map(a => a.getAttribute('href')));
check('diagnostics leads back to the area (breadcrumb)', back.includes('/project_workflow_rules'),
      back.join(' '));
await shot(page, '03-diagnostics');

// --- scenario 4: no banner on a verified host -----------------------------
await page.goto(`${BASE}/project_workflow_rules`, { waitUntil: 'domcontentloaded' });
check('no compatibility banner on a verified host (F05)',
      (await page.$$('#content div.warning')).length === 0);

// --- scenario 5: the transitions matrix for one tracker and role ----------
await page.goto(`${BASE}/project_workflow_rules/edit?tracker_id[]=1&role_id[]=1`,
                { waitUntil: 'domcontentloaded' });
check('the generic transitions matrix renders a grid',
      (await page.$$('table.transitions')).length > 0 || (await page.$$('table.list')).length > 0);
const checked = await page.$$eval('input[type=checkbox][name^="transitions"]:checked', e => e.length);
check('the generic workflow shows its rules as ticked boxes', checked > 0, `${checked} ticked`);
await shot(page, '05-generic-matrix');

console.log('\nerrors seen on these pages:', page.__errors.length);
page.__errors.forEach(e => console.log('   ', e));
check('no JavaScript error or failed request on the administration screens',
      page.__errors.length === 0, page.__errors.join(' | '));

await b.close();
console.log(`\n${results.filter(r => r.ok).length}/${results.length} checks passed`);
process.exit(exitCode());
