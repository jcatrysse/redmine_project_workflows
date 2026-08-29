// Regenerates the screenshots in docs/images/. Needs a running server seeded
// by seed.rb *and then* seed_docs.rb; see README.md.
import { chromium } from 'playwright';
const BASE = 'http://127.0.0.1:3000';
const OUT = '/home/user/redmine_project_workflows/docs/images/';

const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
                                  args: ['--no-sandbox'] });

async function session(login, password) {
  const ctx = await b.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded' });
  await page.fill('#username', login);
  await page.fill('#password', password);
  await Promise.all([page.waitForLoadState('domcontentloaded'), page.click('input[name="login"]')]);
  return page;
}

// Crop to the content that is actually there. #content has a min-height, so
// shooting the element leaves a field of white under a short table.
async function shot(page, url, name, selector = '#content') {
  await page.goto(BASE + url, { waitUntil: 'networkidle' });
  await page.mouse.move(0, 0);            // no row left under a hover highlight
  await page.waitForTimeout(200);
  const box = await page.evaluate((sel) => {
    const root = document.querySelector(sel);
    const r = root.getBoundingClientRect();
    let bottom = r.top;
    root.querySelectorAll('*').forEach((n) => {
      const b = n.getBoundingClientRect();
      if (b.height > 0 && b.width > 0 && getComputedStyle(n).visibility !== 'hidden') {
        bottom = Math.max(bottom, b.bottom);
      }
    });
    return { x: r.x - 8, y: r.y - 8, width: r.width + 16,
             height: Math.min(bottom - r.top + 24, 2400) };
  }, selector);
  await page.screenshot({ path: OUT + name + '.png', clip: box });
  console.log('wrote', name);
}

const mgr = await session('mgr', 'testpass1!');
await shot(mgr, '/projects/alpha/settings?tab=project_workflows', 'project-workflow-tab');
await shot(mgr, '/projects/alpha/workflow/transitions?tracker_id=1&role_id=3', 'project-matrix');
await shot(mgr, '/projects/alpha/workflow/graph?tracker_id=1&role_id[]=3', 'workflow-diagram');
await shot(mgr, '/projects/alpha/workflow/compare?tracker_id=1&role_id=3&rule_type=transitions', 'compare');

// The issue-form panel sits beside the Status field on the edit form and is
// loaded when you click it.
await mgr.goto(`${BASE}/issues/1/edit`, { waitUntil: 'networkidle' });
const link = mgr.locator('a[href*="workflow_map"]').first();
console.log('workflow_map links on the edit form:', await link.count());
if (await link.count()) {
  await link.click({ force: true });
  await mgr.waitForTimeout(1500);
  const modal = await mgr.$('#ajax-modal');
  if (modal && await modal.isVisible()) {
    await modal.screenshot({ path: OUT + 'issue-workflow-panel.png' });
    console.log('wrote issue-workflow-panel');
  } else {
    console.log('panel not visible; falling back to the standalone page');
    await mgr.goto(`${BASE}/issues/1/workflow_map`, { waitUntil: 'networkidle' });
    const el = await mgr.$('#content');
    await el.screenshot({ path: OUT + 'issue-workflow-panel.png' });
    console.log('wrote issue-workflow-panel (standalone)');
  }
}

const admin = await session('admin', 'adminadmin1!');
await shot(admin, '/project_workflow_inventories', 'inventory');
await shot(admin, '/project_workflow_rules/edit?tracker_id[]=1&role_id[]=3&project_id[]=global&project_id[]=1',
           'admin-matrix');
await b.close();
