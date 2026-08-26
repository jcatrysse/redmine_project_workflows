// Exercises the row and column action function in
// app/views/redmine_project_workflows/_bulk_script.html.erb (WP5).
//
// The plugin's suite is RSpec against a real Redmine, which can assert the
// markup the actions are made of but cannot run them. This is the missing half:
// a hand-built DOM, the real function extracted from the partial, and the four
// things it has to get right.
//
//   node dev/check-bulk-js.mjs
//
// It is a manual gate: CI runs Ruby only, so this has to be run by hand (or
// wired into a JS job) when the function changes.
import { readFileSync } from 'node:fs';

const partial = new URL('../app/views/redmine_project_workflows/_bulk_script.html.erb', import.meta.url);
const source = readFileSync(partial, 'utf8');
const body = source.match(/function projectWorkflowBulkApply[\s\S]*?\n}\n/);
if (!body) {
  console.error('FAIL: could not find projectWorkflowBulkApply in the partial');
  process.exit(1);
}

let failures = 0;
let confirmations = [];
let confirmAnswer = true;

function check(what, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures += 1; }
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}${ok ? '' : ` -- got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`}`);
}

// --- the smallest DOM the function needs -------------------------------------
function checkbox({ checked, disabled = false }) {
  return { type: 'checkbox', tagName: 'INPUT', checked, defaultChecked: checked, disabled,
           events: [], dispatchEvent(e) { this.events.push(e.type); } };
}

function select({ value, options, disabled = false }) {
  return { tagName: 'SELECT', value, disabled, options, events: [],
           querySelector(selector) {
             const wanted = selector.match(/option\[value="(.*)"\]/)[1];
             return this.options.includes(wanted) ? { value: wanted } : null;
           },
           dispatchEvent(e) { this.events.push(e.type); } };
}

function run(controls, { value, multiplier = 1, threshold = 50 }) {
  const group = {
    getAttribute(name) {
      return { 'data-project-workflow-target': 'targets',
               'data-project-workflow-multiplier': String(multiplier),
               'data-project-workflow-threshold': String(threshold),
               'data-project-workflow-confirm': 'affects %{count} rules, %{count} again' }[name];
    }
  };
  const link = { parentNode: group, getAttribute: () => value };
  global.document = { querySelectorAll: () => controls };
  global.window = { confirm: (question) => { confirmations.push(question); return confirmAnswer; } };
  global.Event = class { constructor(type) { this.type = type; } };
  // eslint-disable-next-line no-new-func
  new Function(`${body[0]}; projectWorkflowBulkApply(arguments[0]);`)(link);
}

// --- 1. both kinds of control, and the disabled one left alone ---------------
let cells = [checkbox({ checked: false }), checkbox({ checked: true, disabled: true }),
             select({ value: 'no_change', options: ['1', '0', 'no_change'] })];
run(cells, { value: '1' });
check('Yes checks an unchecked box', cells[0].checked, true);
check('Yes leaves the disabled diagonal alone', cells[1].checked, true);
check('Yes sets a mixed cell to 1', cells[2].value, '1');
check('every control it changed says so', [cells[0].events, cells[1].events, cells[2].events],
      [['change'], [], ['change']]);

cells = [checkbox({ checked: true }), select({ value: '1', options: ['1', '0', 'no_change'] })];
run(cells, { value: '0' });
check('No unchecks a checked box', cells[0].checked, false);
check('No sets a mixed cell to 0', cells[1].value, '0');

// --- 2. no change is a return to what the page was opened with ---------------
cells = [checkbox({ checked: true }), select({ value: 'no_change', options: ['1', '0', 'no_change'] })];
cells[0].checked = false;                       // as if somebody had clicked it
cells[1].value = '1';
run(cells, { value: 'no_change' });
check('no change restores a checkbox to its rendered value', cells[0].checked, true);
check('no change puts a mixed cell back to no_change', cells[1].value, 'no_change');

// a cell with no such option -- a project matrix -- is not touched
cells = [select({ value: '1', options: ['1', '0'] })];
run(cells, { value: 'no_change' });
check('a control without the option is left alone', cells[0].value, '1');
check('and is not told it changed', cells[0].events, []);

// --- 3. the confirmation, and the count in it -------------------------------
confirmations = [];
cells = [checkbox({ checked: false }), checkbox({ checked: false }), checkbox({ checked: true })];
run(cells, { value: '1', multiplier: 4, threshold: 5 });
check('it counts only what would change, times the multiplier',
      confirmations, ['affects 8 rules, 8 again']);
check('and goes ahead when the answer is yes', [cells[0].checked, cells[1].checked], [true, true]);

confirmations = [];
confirmAnswer = false;
cells = [checkbox({ checked: false }), checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 4, threshold: 5 });
check('a refused confirmation changes nothing', [cells[0].checked, cells[1].checked], [false, false]);
confirmAnswer = true;

confirmations = [];
cells = [checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 4, threshold: 5 });
check('under the threshold it does not ask', confirmations, []);

confirmations = [];
cells = [checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 1, threshold: 0 });
check('a threshold of zero asks every time', confirmations, ['affects 1 rules, 1 again']);

// --- 4. an action that would change nothing does nothing --------------------
confirmations = [];
cells = [checkbox({ checked: true })];
run(cells, { value: '1', multiplier: 100, threshold: 0 });
check('an action that changes nothing neither asks nor fires', [confirmations, cells[0].events], [[], []]);

console.log(failures === 0 ? '\nbulk action script OK' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
