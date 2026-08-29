import { BASE, browser, newPage, login, shot, check, results, exitCode } from './lib.mjs';

const b = await browser();

async function status(page, url) {
  const r = await page.goto(BASE + url, { waitUntil: 'domcontentloaded' });
  return r.status();
}

// --- who may reach what ----------------------------------------------------
{
  const page = await newPage(b);
  // Anonymous.
  check('anonymous is sent to log in for the administration area',
        [302, 200].includes(await status(page, '/project_workflow_rules')) &&
        /\/login/.test(page.url()), page.url());
  check('anonymous is sent to log in for the diagnostics page',
        /\/login/.test((await status(page, '/project_workflow_diagnostics'), page.url())), page.url());

  // A logged-in user who is nobody special.
  await login(page, 'look', 'testpass1!');
  check('a plain user gets 403 on the administration area',
        (await status(page, '/project_workflow_rules')) === 403);
  check('a plain user gets 403 on the diagnostics page',
        (await status(page, '/project_workflow_diagnostics')) === 403);
  check('a plain user gets 403 on the inventory',
        (await status(page, '/project_workflow_inventories')) === 403);

  // The onlooker holds Developer in alpha, which has view but not manage.
  const s = await status(page, '/projects/alpha/workflow/transitions?tracker_id=1&role_id=3');
  check('a viewer may read a project workflow they hold view on', s === 200, `status ${s}`);
  const editable = await page.locator('#workflow_form').count();
  check('but is not given an editable form', editable === 0);
  check('and is not offered the actions that would change it',
        (await page.locator('a', { hasText: 'Give own workflow (copy of the generic one)' }).count()) === 0);
  await shot(page, '30-viewer-readonly');

  // INV-7: a project route cannot reach another project.
  const other = await status(page, '/projects/beta/workflow/transitions?tracker_id=1&role_id=3');
  check('a viewer with no role in another project is refused there (INV-7)',
        other === 403 || other === 404, `status ${other}`);
  await page.context().close();
}

// --- F03: a selection naming something that does not exist -----------------
{
  const page = await newPage(b);
  await login(page, 'admin', 'adminadmin1!');
  const shapes = {
    'a tracker id that names nothing': '/project_workflow_rules/edit?tracker_id[]=999999&role_id[]=3',
    'a float-shaped tracker id': '/project_workflow_rules/edit?tracker_id[]=1e5&role_id[]=3',
    'a tracker id with trailing garbage': '/project_workflow_rules/edit?tracker_id[]=1abc&role_id[]=3',
    'a live tracker and one that names nothing': '/project_workflow_rules/edit?tracker_id[]=1&tracker_id[]=999999&role_id[]=3',
    'a role id that names nothing': '/project_workflow_rules/edit?tracker_id[]=1&role_id[]=999999',
    'a float-shaped role id': '/project_workflow_rules/edit?tracker_id[]=1&role_id[]=1e5',
    'a project id that names nothing': '/project_workflow_rules/edit?tracker_id[]=1&role_id[]=3&project_id[]=999999',
    'a float-shaped project id': '/project_workflow_rules/edit?tracker_id[]=1&role_id[]=3&project_id[]=1e5',
  };
  for (const [name, url] of Object.entries(shapes)) {
    const s = await status(page, url);
    check(`404 for ${name} (F03)`, s === 404, `status ${s}`);
  }
  const good = await status(page, '/project_workflow_rules/edit?tracker_id[]=1&role_id[]=3');
  check('and 200 for the same request with everything resolvable', good === 200, `status ${good}`);
  await shot(page, '31-f03-refused');
  await page.context().close();
}

await b.close();
console.log(`\n${results.filter(r => r.ok).length}/${results.length} checks passed`);
process.exit(exitCode());
