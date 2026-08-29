# Review run — 2026-08-29 — Claude Code (Opus), in a real browser

- **Reviewer:** Claude Code (Opus 5), driving Chromium through Playwright
- **Commit reviewed:** `6c3992f`
- **Ran the test suite:** yes — 1,335 examples, 0 failures, 23 pending on Redmine
  5.1 with SQLite, plus **CI run 194 green on all eleven jobs** (Redmine 5.1, 6.1
  and 7.0 × PostgreSQL, MySQL and MariaDB, plus RuboCop and the JavaScript gate).
- **Scope covered:** the thing no other gate in this repository does — the plugin
  **rendered and clicked**, on a real Redmine with real data. A development host
  was built (Redmine 5.1, SQLite), seeded with three projects, three roles, three
  trackers, six statuses, a generic workflow of 153 transitions and four users of
  different privilege, and five scenario scripts drove Chromium through it:
  **67 assertions, all passing**. What they cover: the administration area and
  its four screens; the project settings tab and both project matrices; the
  three states of INV-3 including the effect of an own *empty* workflow on a real
  issue form; authorization for anonymous, a plain user, a viewer and a manager;
  the twelve bad-selection shapes of F03; the compatibility banner on all seven
  screens with the manifest doctored so the host measures as drifted; the
  inventory, the copy screen, the comparison screen and the workflow drawing; and
  every page checked for JavaScript errors and failed requests.
- **Scope NOT covered:** one Redmine (5.1) and one database (SQLite) — the
  `pg` gem cannot be built in this container. One browser (Chromium); no Firefox,
  no Safari, no mobile viewport. No screen reader, so accessibility beyond
  "colour is not the only signal" is unchecked. No neighbouring plugins. The
  bulk row/column JavaScript was confirmed *present* on the page but its clicks
  were not driven.

## Summary

The plugin does in a browser what its specs say it does. Every flow an
administrator or a project manager would actually perform worked, looked like
Redmine, and left the right rows in the database — including the three flows that
matter most and are hardest to get right: taking a workflow over, emptying one,
and giving it back. The own *empty* workflow really does remove every status
option from the issue form, and returning to the generic workflow really does
restore them; the rule a project removed from its own workflow really is
untouched in what its neighbours inherit (INV-1). The compatibility banner
appears on all seven screens the moment the host stops being one the plugin is
tested against, links to the diagnostics page for an administrator and not for
anybody else, and blocks nothing.

Three times this run I thought I had found a defect and had not, which is worth
recording because the next reviewer will hit the same three. They are in
*Checked and found sound* below.

One real thing, and it is a nit: on the project settings tab, three pieces of
text in the same cell run together with nothing between them, in a plugin that
elsewhere took the trouble to separate exactly this kind of pair and wrote down
why.

**Counts:** blocker 0 · major 0 · minor 0 · nit 1 · question 0

---

### F01 — Three adjacent links in the settings-tab cell run together as one sentence

- **Status:** open
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** ux
- **Where:** `app/views/project_workflows/_settings_tab.html.erb:56-65`
- **Invariant touched:** none

**What is wrong**

Inside `div.project-workflow-cell-details` the audit line, the comparison link
and the drawing link are emitted one after another with no separator. Rendered,
the first row of the tab reads:

```
Updated by Maria Manager less than a minute ago Compare with the generic workflow Workflow diagram
```

Three things: a sentence and two links, with nothing to say where one ends. The
sibling partial `_scope_actions.html.erb` has the identical situation for its own
pair and solves it with a pipe, and its comment explains at length why —
*"Without it the browser renders 'Give own workflow (copy of the generic one)
Give own empty workflow' as one sentence and the reader has to find the seam"*.
That reasoning applies here and was not applied here.

**Why it matters**

It is a nit and is marked one: nothing is wrong, nothing is unreachable, and a
reader who looks twice finds the links. But it is the plugin being inconsistent
with a rule it wrote down for itself two files away, on the screen a project
manager uses most.

**How I verified it**

Rendered in Chromium on a Redmine 5.1 host and read off the screenshot
(`11-settings-tab-own.png` of the browser run), then confirmed in the template:
lines 57, 58 and 63 emit three helpers into one `div` with only ERB whitespace
between them.

**Suggested direction**

The same separator the neighbouring partial uses, between the links — and the
audit line probably wants to be its own block rather than sharing a line with
them, since it is a sentence and they are actions. Whatever is chosen, the two
files should agree, and the comment in `_scope_actions` is where the reasoning
already lives.

**Resolution:**

---

## Checked and found sound

Recorded so the next reviewer does not spend the time again — and because all
three of these looked like defects until they were run down.

- **A project route answering 404 for `role_id=1` is correct.** Redmine gives ids
  1 and 2 to the built-in Non-member and Anonymous roles, so on a fresh
  installation the first *givable* role is id 3. A hand-built URL naming role 1
  is naming a role the project does not offer, and the plugin refuses it exactly
  as INV-7 says it should. A first version of the browser script hardcoded id 1
  and reported the refusal as a defect.
- **The comparison screen answering 404 without `rule_type` is correct.** Every
  link the plugin renders to it carries one; a comparison of nothing in
  particular is not a page. Follow the link rather than building the URL.
- **An own EMPTY workflow removes the Status field from the issue form
  entirely**, rather than leaving one dead option. That is Redmine's own
  rendering, not the plugin's: `app/views/issues/_attributes.html.erb` shows the
  field only `if @allowed_statuses.present?`, and core's
  `new_statuses_allowed_to` adds the current status only when something else is
  allowed. The README now says so, because it is what an administrator will see
  and report.
- **`net::ERR_ABORTED` on Redmine's own theme images is not a missing asset.**
  Navigating away cancels whatever subresources the previous page still had in
  flight, and a script that clicks through several screens produces it
  constantly. The files are on disk and served.
- **Everything else listed under *Scope covered* passed**, including all twelve
  bad-selection shapes of F03 answering 404 with nothing written, and every page
  visited being free of JavaScript errors and failed requests.
