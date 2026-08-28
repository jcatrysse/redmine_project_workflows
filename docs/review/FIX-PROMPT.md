# Fixer prompt — act on the review findings

Paste this into a fresh session. You are the **fixer**: you read every open
finding, you act on each one, and you leave none at `open` without saying why.

## 0. Branch — before anything else

```bash
git fetch origin --prune
git checkout -B claude/dev origin/claude/dev
git merge-base --is-ancestor claude/dev origin/claude/dev && echo "in sync"
```

`CLAUDE.md` pins this branch and it overrides whatever name the environment
gave this session.

`checkout -B` rather than `checkout` and `pull --ff-only`. The local
`claude/dev` in a fresh container can have a history **unrelated** to the
remote's — no merge base at all — and then `pull --ff-only` aborts with "Not
possible to fast-forward" while `git status` reports something like "5 and 50
different commits", which reads like local work worth preserving and is not.
Do not diagnose that with `git merge-base A B` piped into anything: an *empty*
merge base piped into `xargs git log -1` prints **HEAD**, which looks exactly
like a merge base that happens to be your own commit. `--is-ancestor` and its
exit status cannot mislead.

Findings files live on **this** branch, beside the code they describe — answered
**B** by Jan on 2026-08-28, so there is nothing to fetch from `main` and nothing
to bring across:

```bash
git log --oneline -8 -- docs/review/findings/   # has a reviewer pushed since you branched?
```

You answer the file in place: its `Status:` and `Resolution:` lines are yours to
update, and the reviewer's original wording stays readable through
`git show <review-commit>:docs/review/findings/<file>`.

Then read `CLAUDE.md` and `docs/STATE.md`.

## 1. Find the work

```bash
grep -rn '^- \*\*Status:\*\* open' docs/review/findings/
```

Read every one before fixing any of them. Findings from different runs overlap,
and the second one often explains the first.

## 2. Order

Blockers, then majors, then the rest. Within that: fixes that share a component
together, so one round of the four roles covers them.

A finding that touches an invariant (INV-1..9 in `CLAUDE.md`) is not yours to
resolve by relaxing the invariant. Set it to `question` and say so.

## 3. For each finding

1. **Reproduce it first.** A finding you cannot reproduce is `invalid` — but
   say what you tried, because "I could not reproduce it" and "it does not
   happen" are different claims.
2. **Write the test before the fix.** It must be red on the current code. State
   in the `Resolution:` line how you know it was.
3. **Fix the defect, not the symptom.** If the same shape appears in three
   places, fix three places and say so — this repository has already had four
   findings that were one rule held in one of two places.
4. **Update the finding in place:** set `Status:` and write a `Resolution:`
   line saying what you did and how you verified it. Do not edit anything else
   in someone else's findings file.
5. **Anything user-visible that you decide rather than repair** goes into
   `docs/DECISIONS.md`.

## 4. Gates before you commit

Reversibility **first** — the suite wipes the plugin's migration bookkeeping,
after which `VERSION=0` silently does nothing and proves nothing:

```bash
cd .redmine/<host>
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0
bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
```

Then, from the plugin root:

```bash
dev/run.sh .redmine/<host>                    # at least 5.1 and 7.0
BUNDLE_GEMFILE=.github/lint/Gemfile bundle exec rubocop
```

G2 means you ran the suite and saw the output. Never claim it otherwise.

## 5. Commit and push

One commit per coherent group of findings. The message names the findings it
closes, what changed, and one line of gate evidence. Push after each commit and
verify it landed:

```bash
git push -u origin claude/dev
git ls-remote --heads origin
```

## 6. Finish

- Rewrite `docs/STATE.md` in full, as if the next session knows nothing.
- Any finding still `open` needs a `Resolution:` line saying why. "Ran out of
  time" is acceptable; silence is not.
- End with the session report from `CLAUDE.md`.
