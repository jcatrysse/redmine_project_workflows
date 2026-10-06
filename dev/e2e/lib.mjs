import { chromium } from 'playwright';

export const BASE = 'http://127.0.0.1:3000';
// Screenshots land beside the scripts unless E2E_SHOTS says otherwise. They are
// evidence for a session report, not fixtures: nothing asserts on them, and the
// directory is deliberately not committed.
export const SHOTS = process.env.E2E_SHOTS || new URL('./shots/', import.meta.url).pathname;

export const results = [];
let failures = 0;

export function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -- ' + detail : ''}`);
}

export function exitCode() { return failures === 0 ? 0 : 1; }

export async function browser() {
  return chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
                           args: ['--no-sandbox'] });
}

// A page that records every console error and every failed request, so a
// screen that "looks right" but broke its own JavaScript is not reported green.
export async function newPage(b) {
  const ctx = await b.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  page.__errors = [];
  page.on('console', m => { if (m.type() === 'error') page.__errors.push('console: ' + m.text()); });
  page.on('pageerror', e => page.__errors.push('pageerror: ' + e.message));
  // ERR_ABORTED is not a failure: navigating away cancels whatever subresources
  // the previous page still had in flight, and a script that clicks through
  // several screens in a row produces it constantly. Everything else counts.
  page.on('requestfailed', r => {
    const u = r.url();
    const why = r.failure()?.errorText || '';
    if (u.startsWith(BASE) && !why.includes('ERR_ABORTED')) {
      page.__errors.push('requestfailed: ' + u + ' ' + why);
    }
  });
  page.on('response', r => {
    if (r.status() >= 400 && r.url().startsWith(BASE)) page.__errors.push(`http ${r.status()}: ${r.url()}`);
  });
  return page;
}

export async function login(page, login, password) {
  await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded' });
  await page.fill('#username', login);
  await page.fill('#password', password);
  await Promise.all([page.waitForLoadState('domcontentloaded'), page.click('input[name="login"]')]);
}

export async function shot(page, name) {
  await page.screenshot({ path: `${SHOTS}${name}.png`, fullPage: true });
}
