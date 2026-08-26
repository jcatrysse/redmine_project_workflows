# Code review — how the loop works

This directory exists so that a review done in **one** session can be acted on
in **another**, without a human retyping the findings.

Three roles, three prompts, one shared file format:

| Role | Prompt | Writes | Touches code? |
| --- | --- | --- | --- |
| **Reviewer** | `PROMPT.md` | one findings file under `findings/` | **no** |
| **Fixer** | `FIX-PROMPT.md` | code and tests, plus the `Status:` / `Resolution:` lines of the findings it handled | yes |
| **Curator (Jan)** | — | decides `question` and `wont-fix` items | no |

## The cycle

```
review session  ->  findings file committed to main
                        |
fix session     ->  reads every open finding, fixes or answers each one,
                    updates its Status, pushes to claude/dev
                        |
review session  ->  a new run, a new findings file (never edits an old one)
```

Expect several rounds. That is the point: each run gets its own file, so the
history of what was found and what was done about it stays readable.

## Branches

| Role | Reviews | Pushes to |
| --- | --- | --- |
| **Reviewer** | the head of `main` | its findings file, to `main` |
| **Fixer** | `claude/dev` | `claude/dev` only |

`CLAUDE.md` pins the development branch and keeps code off `main`. A reviewer's
findings file is the single documented exception, because other sessions have
to be able to see it. If the push is refused, commit where you stand and print
the file rather than silently dropping it.

Verify a push landed — `git ls-remote --heads origin` — rather than assuming.

## Finding your work

Every open finding, across every run:

```bash
grep -rn '^- \*\*Status:\*\* open' docs/review/findings/
```

Open blockers and majors only:

```bash
grep -rn -A2 '^- \*\*Status:\*\* open' docs/review/findings/ | grep -E 'blocker|major'
```

Count what is left:

```bash
grep -rhc '^- \*\*Status:\*\* open' docs/review/findings/ | paste -sd+ | bc
```

## Status values

| Status | Meaning | Who sets it |
| --- | --- | --- |
| `open` | not yet acted on | reviewer (initial) |
| `fixed` | changed, with a test that fails on the old code | fixer |
| `invalid` | factually wrong — say why, with evidence | fixer |
| `wont-fix` | real, deliberately not changed — needs a recorded reason, and for anything user-visible a line in `docs/DECISIONS.md` | fixer |
| `duplicate` | same as another finding — name it | fixer |
| `deferred` | real, worth doing, out of this session's scope — must name what it waits on | fixer |
| `adjusted` | real, but the severity or the fix changed after verification — the `Resolution:` line says how | fixer |
| `question` | needs Jan, not code | reviewer or fixer |

A fixer leaves **no** finding at `open` without saying why in its `Resolution:`
line. "Ran out of time" is an acceptable reason; silence is not.

## Rules that keep the loop honest

1. **A reviewer never changes code.** A review that also refactors cannot be
   audited, and a reviewer who has already written the fix stops looking for
   reasons the fix is wrong.
2. **A fixer never weakens a test to close a finding.** If an assertion is
   genuinely wrong, say so explicitly in the `Resolution:` line — that is a
   finding of its own.
3. **Every fix carries a test that is red on the old code.** State how you know.
4. **The invariants in `CLAUDE.md` (INV-1..9) are not review targets.** A
   finding that proposes relaxing one is a `question` for Jan, never a fix.
5. **Do not re-file what is already decided.** `docs/DECISIONS.md` records every
   deliberate choice.
6. **Say what you did not run.** A findings file that does not state whether the
   suite was executed, and on which Redmine version and database, cannot be
   weighted. `dev/setup.sh` exists so that "I could not run it" is a choice.
