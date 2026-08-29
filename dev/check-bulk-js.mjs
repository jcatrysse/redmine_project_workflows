// Exercises the row and column action script in
// app/views/redmine_project_workflows/_bulk_script.html.erb (WP5, WP6).
//
// The plugin's suite is RSpec against a real Redmine, which can assert the
// markup the actions are made of but cannot run them. This is the missing half:
// a hand-built DOM, the real script extracted from the partial, and one check
// per thing it has to get right.
//
//   node dev/check-bulk-js.mjs
//
// CI runs it: the `Bulk action script` job in .github/workflows/specs.yml,
// beside RuboCop (finding F07). It needs no Redmine, no database and no gems, so
// it is a checkout and one command. Run it by hand too when the script changes —
// a second of feedback beats a push.
//
// The whole javascript_tag block is extracted and evaluated ONCE, not one
// function at a time: the undo stack (WP6) is state the functions share, so
// re-evaluating per case would reset it and every undo check would pass
// vacuously.
import { readFileSync } from 'node:fs';

const partial = new URL('../app/views/redmine_project_workflows/_bulk_script.html.erb', import.meta.url);
const source = readFileSync(partial, 'utf8');
const block = source.match(/<%= javascript_tag do %>([\s\S]*?)\n<% end %>/);
if (!block) {
  console.error('FAIL: could not find the javascript_tag block in the partial');
  process.exit(1);
}

function loadScript() {
  // eslint-disable-next-line no-new-func
  return new Function(
    `${block[1]}\nreturn [projectWorkflowBulkApply, projectWorkflowBulkUndo, projectWorkflowConfirmSave];`
  )();
}

let [bulkApply, bulkUndo, confirmSave] = loadScript();

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

// The undo region (WP6): the two message templates, the element the count is
// written into, and the undo link whose visibility follows the stack.
function undoRegion() {
  const message = { textContent: '' };
  // style.display starts as the rendered default -- the link is visible in the
  // markup and the script is what hides it. Starting it at 'none' would make
  // the focus check below pass for the wrong reason (F15).
  const undoLink = { style: { display: '' } };
  const self = {
    style: {},
    message,
    undoLink,
    focused: 0,
    // tabindex="-1" on the region is what makes this callable; _bulk_undo sets it.
    focus() { this.focused += 1; global.document.activeElement = self; },
    getAttribute(name) {
      return { 'data-project-workflow-changed': 'changed %{cells} cells, %{rules} rules',
               'data-project-workflow-undone': 'undone %{cells} cells, %{rules} rules' }[name];
    },
    querySelector(selector) {
      return selector.includes('message') ? message : undoLink;
    }
  };
  return self;
}

// null means "a page that renders the actions without the region", which the
// script has to survive rather than throw on.
let region = undoRegion();

// A fresh script and a fresh region. The undo stack is state the script holds
// for the life of a page, so a scenario that asserts anything about it has to
// start from an empty one -- otherwise every "there is nothing left to undo"
// check passes or fails on what an earlier scenario happened to leave behind.
// This is how the first version of these checks went wrong.
function reset() {
  [bulkApply, bulkUndo, confirmSave] = loadScript();
  region = undoRegion();
}

function install(controls) {
  global.document = { querySelectorAll: () => controls, getElementById: () => region,
                      activeElement: (global.document && global.document.activeElement) || null };
  global.window = { confirm: (question) => { confirmations.push(question); return confirmAnswer; } };
  global.Event = class { constructor(type) { this.type = type; } };
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
  install(controls);
  bulkApply(link);
}

function undo(controls) {
  install(controls);
  bulkUndo();
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
reset();
confirmations = [];
cells = [checkbox({ checked: true })];
run(cells, { value: '1', multiplier: 100, threshold: 0 });
check('an action that changes nothing neither asks nor fires', [confirmations, cells[0].events], [[], []]);
check('and says nothing, so the region stays as it was', region.message.textContent, '');

// --- 5. the counter and the undo (WP6) --------------------------------------
reset();
cells = [checkbox({ checked: false }), checkbox({ checked: false }), checkbox({ checked: true })];
run(cells, { value: '1', multiplier: 3 });
check('the counter names the cells it changed and the rules that costs',
      region.message.textContent, 'changed 2 cells, 6 rules');
check('the region is shown', region.style.display, '');
check('and the undo is offered', region.undoLink.style.display, '');

undo(cells);
check('undo puts the checkboxes back', [cells[0].checked, cells[1].checked, cells[2].checked],
      [false, false, true]);
check('and says what it put back', region.message.textContent, 'undone 2 cells, 6 rules');
check('and withdraws itself once there is nothing left to undo',
      region.undoLink.style.display, 'none');
check('while the sentence stays readable', region.style.display, '');

// The value undo restores is the one held BEFORE the action, not the one the
// page was opened with -- and those differ from the second action onwards.
reset();
cells = [select({ value: 'no_change', options: ['1', '0', 'no_change'] })];
run(cells, { value: '1', multiplier: 1 });
run(cells, { value: '0', multiplier: 1 });
undo(cells);
check('undo steps back one action, not all the way to the start', cells[0].value, '1');
undo(cells);
check('a second undo steps back again', cells[0].value, 'no_change');
check('and the undo is gone', region.undoLink.style.display, 'none');

undo(cells);
check('undo on an empty stack changes nothing', cells[0].value, 'no_change');
check('and says so rather than throwing', region.message.textContent, 'undone 0 cells, 0 rules');

// --- 5b. focus when the undo link withdraws itself (F15) ---------------------
//
// A keyboard user who activates undo until the stack empties has focus on the
// undo link, and the script then hides it. Hiding the element that holds focus
// drops focus to <body>, so the next Tab restarts at the top of the page -- past
// the aria-live sentence that has just changed. The region takes focus instead
// (tabindex="-1" in _bulk_undo.html.erb).
reset();
cells = [checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 1 });
global.document.activeElement = region.undoLink;
undo(cells);
check('focus moves to the region before the undo link is hidden', region.focused, 1);
check('and lands on the region rather than nowhere', global.document.activeElement === region, true);
check('the link is hidden all the same', region.undoLink.style.display, 'none');

// Focus is not stolen from wherever the user actually is. Somebody who clicked
// a row action and then tabbed on has focus elsewhere; the region must not
// yank it back just because the stack emptied.
reset();
cells = [checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 1 });
const elsewhere = { name: 'some other control' };
global.document.activeElement = elsewhere;
undo(cells);
check('focus is left alone when it is not on the undo link', region.focused, 0);
check('and stays where the user put it', global.document.activeElement === elsewhere, true);

// An undo on an already-empty stack must not move focus either: the link is
// already hidden, so there is nothing to take focus away from.
reset();
cells = [checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 1 });
undo(cells);
const focusedAfterFirst = region.focused;
global.document.activeElement = region.undoLink;
undo(cells);
check('a further undo on an empty stack does not move focus again',
      region.focused, focusedAfterFirst);


// A refused confirmation must not leave an entry behind for undo to "restore".
reset();
confirmAnswer = false;
confirmations = [];
cells = [checkbox({ checked: false }), checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 4, threshold: 1 });
undo(cells);
check('a refused action leaves nothing on the undo stack',
      [cells[0].checked, cells[1].checked, region.message.textContent],
      [false, false, 'undone 0 cells, 0 rules']);
confirmAnswer = true;

// A page that renders the actions without the region.
reset();
region = null;
cells = [checkbox({ checked: false })];
run(cells, { value: '1', multiplier: 1 });
check('an action still works with no region on the page', cells[0].checked, true);
undo(cells);
check('and so does the undo behind it', cells[0].checked, false);

// --- the Save button's own confirmation (WP13, audit F08) --------------------
//
// It counts what the form will actually submit and multiplies by the workflows
// the selection covers, which is the same unit the row and column actions use
// and the same number the server computes from the payload it receives.
function saveForm(controls, { multiplier, threshold = 50 }) {
  return {
    getAttribute(name) {
      return { 'data-project-workflow-multiplier': multiplier === undefined ? null : String(multiplier),
               'data-project-workflow-threshold': threshold === undefined ? null : String(threshold),
               'data-project-workflow-save-confirm': 'saving rewrites %{count} rules' }[name];
    },
    querySelectorAll: () => controls
  };
}

function save(controls, options) {
  install(controls);
  return confirmSave(saveForm(controls, options));
}

// A single-workflow save is what Redmine has always done: however many cells the
// status list produces, it must not grow a dialog.
reset();
confirmations = [];
cells = Array.from({ length: 400 }, () => checkbox({ checked: false }));
check('a save of one workflow never asks', save(cells, { multiplier: 1 }), true);
check('and puts no question on the screen', confirmations.length, 0);

// A selection of several workflows, over the threshold: one question, naming
// the number the server will compute.
reset();
confirmations = [];
cells = [checkbox({ checked: false }), checkbox({ checked: true }),
         select({ value: '1', options: ['1', '0', 'no_change'] })];
check('a save over the threshold asks', save(cells, { multiplier: 10, threshold: 20 }), true);
check('and names cells x workflows', confirmations, ['saving rewrites 30 rules']);

// Under the threshold it goes straight through.
reset();
confirmations = [];
cells = [checkbox({ checked: false })];
check('a save under the threshold does not ask', save(cells, { multiplier: 2, threshold: 20 }), true);
check('and asks nothing', confirmations.length, 0);

// Neither a disabled control nor a cell left at "no change" is submitted, so
// neither is counted -- which is what keeps this number equal to the server's.
reset();
confirmations = [];
cells = [checkbox({ checked: false }), checkbox({ checked: false, disabled: true }),
         select({ value: 'no_change', options: ['1', '0', 'no_change'] })];
check('a save counts neither a disabled cell nor a "no change" one',
      save(cells, { multiplier: 10, threshold: 5 }), true);
check('so it asks about the one cell that will be submitted', confirmations, ['saving rewrites 10 rules']);

// Declining stops the submit.
reset();
confirmations = [];
confirmAnswer = false;
cells = [checkbox({ checked: false })];
check('declining the question stops the save', save(cells, { multiplier: 10, threshold: 5 }), false);
confirmAnswer = true;

// A page whose attributes are missing submits: this is a courtesy in front of
// the server's ceiling, never the thing enforcing it.
reset();
confirmations = [];
cells = [checkbox({ checked: false })];
check('a form with no multiplier submits', save(cells, { multiplier: undefined }), true);
check('a form with no threshold submits', save(cells, { multiplier: 10, threshold: undefined }), true);
check('and neither asked anything', confirmations.length, 0);

console.log(failures === 0 ? '\nbulk action script OK' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
