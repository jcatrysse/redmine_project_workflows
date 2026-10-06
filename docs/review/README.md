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
review session  ->  reviews claude/dev, commits its findings file to claude/dev
                        |
fix session     ->  reads every open finding in that file, fixes or answers each
                    one, updates its Status and Resolution in place, pushes to
                    claude/dev -- one copy, so there is nothing to keep in step
                        |
review session  ->  a new run, a new findings file (never edits an old one)
```

Expect several rounds. That is the point: each run gets its own file, so the
history of what was found and what was done about it stays readable.

## Branches

| Role | Reviews | Pushes to |
| --- | --- | --- |
| **Reviewer** | the head of `claude/dev` | its findings file, to `claude/dev` |
| **Fixer** | `claude/dev` | `claude/dev` only |

**Everything in this loop lives on `claude/dev`. Nothing goes to `main`** —
answered **B** by Jan on 2026-08-28. `main` means "last released"; the branch is
pinned in `CLAUDE.md` and there is now no exception to it, for findings any more
than for code.

A reviewer reviews `claude/dev` rather than `main` for the reason Jan gave on
2026-08-27 (finding F09 of that day's review): `main` is a long way behind — at
the time of that answer it stood three commits from before 0.1.0 while
`claude/dev` carried eight work packages and three review rounds more — so a
reviewer following the old instruction would spend a session on code that no
longer exists. The findings file now follows the code it describes.

What the older arrangement bought, and what replaces it: a copy on `main` kept
the findings as the reviewer wrote them, because a fixing session answered a
separate copy on `claude/dev`. With one copy that is no longer needed — the
original wording is in git, and `git show <review-commit>:docs/review/findings/<file>`
prints exactly what the reviewer wrote. One copy also removes the trap the old
arrangement had: two files with the same name and different `Status:` lines, and
a reader with no way to tell which one they had opened.

Still worth knowing, because it will bite a merge rather than a review: the two
branches' histories are **unrelated** — `git merge-base main claude/dev` prints
nothing — so a merge, when Jan wants one, needs `--allow-unrelated-histories`.

If a push is refused, commit where you stand and print the file rather than
silently dropping it.

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
