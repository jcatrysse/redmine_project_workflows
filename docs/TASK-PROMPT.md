# Session prompts

**The normal case needs no template.** Every session ends by rewriting
`docs/STATE.md`, so the prompt for the next one is:

```
Read CLAUDE.md and docs/STATE.md. Carry on.
```

That session then reads both, picks up the exact next step, works through as
many work packages as its context allows (four roles and seven gates per
package, per CLAUDE.md), decides Class A questions itself, logs Class B choices
in `docs/DECISIONS.md` with a recommendation and keeps building on a safe
default, stops cleanly on Class C, rewrites `docs/STATE.md`, and ends with the
session report.

A finished work package is a commit and a push, then straight on to the next —
not a checkpoint to report back from.

## Override template

Use this only to deviate from the default flow: skip ahead, redo a package,
inject information a fresh session cannot know. It deliberately does not
restate CLAUDE.md.

```
Read CLAUDE.md. Work package: **WP-N — <title>** from docs/implementation-plan.md.

Landed so far: <one line per finished package>.

In scope: exactly WP-N as specified. Out of scope this turn: <the next
package>, refactors outside the components it touches, UI polish not named.

You may assume: <decisions or measurements that affect this package>.

I cannot provide: <e.g. "a production database to test the backfill against —
use a seeded copy">.

Done for this turn: WP-N's goal demonstrably met; suite green on at least
Redmine 5.1 and 7.0; rubocop clean; a short report of what landed, what you
verified, and anything found but NOT fixed.
```

## Review sessions

A review session is not a normal session. It reads `docs/review/PROMPT.md`,
writes one findings file, and touches no code. A session that acts on findings
reads `docs/review/FIX-PROMPT.md`. See `docs/review/README.md`.

## Session hygiene

- Finish a package, push, start the next. One line of progress between them at
  most; the full report comes once, at the end.
- If a package turns out to be two, split it, say so, and carry on with the
  first half.
- A green suite never excuses an invariant violation. INV-1..9 outrank tests.
- Anything found outside the current package is reported, not fixed.
