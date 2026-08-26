<!-- Copy this file to docs/review/findings/YYYY-MM-DD-<reviewer>.md and fill it in.
     Do not commit changes to this template itself. -->

# Review run — YYYY-MM-DD — <reviewer>

- **Reviewer:** <tool + model, e.g. "Claude Code (Opus)" or "ChatGPT Codex">
- **Commit reviewed:** `<git rev-parse --short HEAD>`
- **Ran the test suite:** yes / no — <on which Redmine version and database; `dev/setup.sh` builds any of the nine. If no, say why; it changes how findings should be read>
- **Scope covered:** <which dimensions from PROMPT.md you actually got to>
- **Scope NOT covered:** <be explicit — an unstated gap reads as "clean">

## Summary

<Three to eight sentences in plain language. What is the state of this codebase,
what worried you most, what surprised you positively. No jargon without a
one-line explanation — Jan reads this part.>

**Counts:** blocker <n> · major <n> · minor <n> · nit <n> · question <n>

---

### F01 — <one-line title, the claim itself>

- **Status:** open
- **Severity:** blocker | major | minor | nit | question
- **Confidence:** confirmed | probable | speculative
- **Category:** correctness | security | privacy | performance | concurrency | portability | ui | ux | i18n | spec-conformance | code-quality | test-quality | docs | operability | accessibility | dependency | build
- **Where:** `path/to/file.rb:123` <, plus other paths if the finding spans them>
- **Invariant touched:** INV-1..9 from CLAUDE.md, or none

**What is wrong**

<One paragraph. State the defect, not the symptom.>

**Why it matters**

<A concrete failure path: these inputs or this state → this wrong outcome. If you
cannot write this sentence, the finding is probably a nit or speculative — mark it
so rather than inflating it.>

**How I verified it**

<The command you ran and what it printed, the test you wrote, or plainly:
"read-only, not executed". Never imply verification you did not do.>

**Suggested direction**

<What good would look like — not a patch. The fixing session owns the design, and
a finding that dictates the implementation hides the reasoning behind it.>

**Resolution:** <left empty by the reviewer; the fixing session fills this in>

---

### F02 — ...
