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
review session  ->  reviews claude/dev, commits its findings file to main
                        |
fix session     ->  brings that file onto claude/dev, reads every open finding,
                    fixes or answers each one, updates its Status, pushes to
                    claude/dev -- so main's copy keeps the original statuses
                        |
review session  ->  a new run, a new findings file (never edits an old one)
```

Expect several rounds. That is the point: each run gets its own file, so the
history of what was found and what was done about it stays readable.

## Branches

| Role | Reviews | Pushes to |
| --- | --- | --- |
| **Reviewer** | the head of `claude/dev`, unless Jan says otherwise | its findings file, to `main` |
| **Fixer** | `claude/dev` | `claude/dev` only |

A reviewer reviews **`claude/dev`, not `main`** — answered **A** by Jan on
2026-08-27, on finding F09 of that day's review. `main` means "last released",
and it is a long way behind: at the time of that answer it stood at `6c17b31`,
three commits from before 0.1.0, while `claude/dev` carried eight work packages
and three review rounds more. A reviewer who took the old instruction literally
would spend a session on code that no longer exists, and the file format records
the commit without checking it against the branch. Two consequences worth
knowing:

* the two branches' histories are **unrelated** — `git merge-base main claude/dev`
  prints nothing — so `main` is not an ancestor of anything you are reviewing,
  and a merge, when Jan wants one, needs `--allow-unrelated-histories`;
* a findings file therefore lives on `main` while the code it describes lives on
  `claude/dev`. A fixer brings the file across (`FIX-PROMPT.md` says how) and
  answers it **there**, so once a fixing session has run, `main`'s copy still
  reads `open` for findings that are closed. Read a findings file from
  `claude/dev` before believing its `Status:` lines.

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
