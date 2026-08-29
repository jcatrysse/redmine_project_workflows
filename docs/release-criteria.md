# Release criteria

> WP16 item 4. This file says what has to be true before a version of this
> plugin is released, and — separately — before the *alpha* warning at the top of
> the README comes off. It is written down so that the answer to "is it ready?"
> is a list somebody can check rather than a feeling somebody has.

Two different questions, deliberately kept apart:

* **Can this be released?** — R1..R9 below. They are the gates for cutting any
  version, alpha or not.
* **Can the alpha warning come off?** — R1..R9 **and** A1..A4. The warning says
  *do not use in production*, and removing it is a claim about installations
  nobody in this project can see.

Neither list is a judgement call. Each line says how it is checked, and a line
that cannot be checked mechanically says who checks it and against what.

## Release criteria

| | Criterion | How it is checked |
|---|---|---|
| **R1** | The nine-cell CI matrix is green on the commit being released — Redmine 5.1, 6.1 and 7.0 × PostgreSQL, MySQL and MariaDB. | The *Specs* workflow, all eleven jobs, on that commit. Not "green on a machine": one host is one of nine. |
| **R2** | `rubocop` is clean through `.github/lint/Gemfile`. | The *RuboCop* job. |
| **R3** | `spec/characterization/` does not exist, or is empty. | Everything in it documents behaviour that is **wrong**; a release with an example still in it ships a known defect with a test asserting it stays. |
| **R4** | Every migration is reversible, and the reversal is rehearsed over data that is already there. | Four CI steps, on every cell: the `VERSION=0` round trip, `dev/check-backfill.sh`, `dev/check-upgrade.sh` and `dev/check-uninstall.sh`. |
| **R5** | An upgrade **from the previous release** is rehearsed, starting from a checkout of that release. | A tag for the previous release, and a script that installs it, populates it, and upgrades the working tree over it. **Not met — see below.** |
| **R6** | No finding in `docs/review/findings/` is still `open`. | `grep '\*\*Status:\*\* open' docs/review/findings/*.md` returns only `TEMPLATE.md`. A `wont-fix` counts as settled; an `open` does not. |
| **R7** | The README describes what the code does. | Read against the code. Where a claim can be pinned it already is: the compatibility section against `compatibility.yml`, the override count against the rendered pages, the settings defaults against their constants. |
| **R8** | All eight locale files carry the same keys, and no English string is presented as a translation. | `spec/locales_spec.rb` asserts the parity; the second half is a reading, and `de`, `es`, `fr`, `it`, `pl` and `pt` are unreviewed translation *presented as* translation (see `CLAUDE.md`). |
| **R9** | The version in `init.rb`, the CHANGELOG's top entry and the tag agree. | Read. The tag is what makes R5 possible for the *next* release, which is why it is a release criterion and not an afterthought. |

## Additional criteria for removing the alpha warning

| | Criterion | How it is checked |
|---|---|---|
| **A1** | The plugin's write actions work on a host carrying every other plugin the maintainer runs. | The 45-plugin compatibility run of 2026-08-28, repeated on the release commit. `docs/STATE.md` has the recipe. This is the run that found the permission-name collision, which made every screen answer 403 to everybody with nothing in any log. |
| **A2** | An installation can be undone. | R4 covers the mechanism; A2 is the documentation of it — a procedure an administrator can follow, including what a downgrade costs. `README.md` § *Upgrading and uninstalling*. |
| **A3** | The plugin has run on a real installation, with real data, for a stated period. | The maintainer's answer. Nothing in this repository can establish it, and no amount of CI substitutes for it. |
| **A4** | The behaviours that surprise people are written down where somebody installing it will read them. | `README.md` § *What to know before you install it*. Each entry is a consequence of the design that has actually surprised somebody. |

## Where this stands — 2026-08-29, version 0.1.6, unreleased

| | State |
|---|---|
| R1 | **met** on the last commit CI has answered for (run 180, `8a2e240`). This one is only ever true of a *commit*, so it says nothing about any later one: re-check it on the release commit itself. |
| R2 | **met.** |
| R3 | **met** — the directory is gone. |
| R4 | **met**, including `dev/check-uninstall.sh`, which is new in this work package. |
| R5 | **not met.** The repository has **no tags at all**, so there is no previous release to check out. `dev/check-upgrade.sh` rehearses the migration path from `VERSION=3` — the migration state an installation on 0.0.3 stands at — over populated data, on all nine cells, which is most of what R5 asks for; what it cannot do is run the *code* of that release. Creating a tag for 0.0.3, which is what `main` carries, is the missing step. |
| R6 | **met** — 85 fixed, 11 wont-fix, 5 adjusted, 2 invalid, 1 archived, 0 open. |
| R7 | **met** as far as it has been read; it is the criterion with the largest gap between "checked" and "true", because most of the README is prose that no spec can pin. |
| R8 | **met** for parity. The second half is a known, accepted cost rather than a gap: six of the eight are unreviewed translation. |
| R9 | **not met.** `init.rb` says 0.1.6, the CHANGELOG's top entry is 0.1.6, and there is no tag. |
| A1 | **not re-run** on this commit. It was run on 2026-08-28 and found two blockers, both since fixed. |
| A2 | **met** as of this work package. |
| A3 | **unanswered.** This is the maintainer's to answer and it is the reason the warning is still there. |
| A4 | **met.** |

**Verdict: the alpha warning stays.** R5, R9 and A1 are mechanical and can be met
in one session once a tag exists; A3 cannot be met by this repository at all.
Removing the warning is a claim about production installations, and the honest
position is that no session can make that claim on the maintainer's behalf.

## Cutting a release, once the criteria pass

1. Check R1..R9 against the commit, not against a memory of an earlier one.
2. Update `init.rb`'s `version` and the CHANGELOG's top entry so they agree.
3. Merge `claude/dev` into `main` — the histories are unrelated, so this needs
   `--allow-unrelated-histories` (see `docs/review/README.md`).
4. Tag the merge commit `v<version>` and push the tag. **The tag is what makes
   the next release's R5 possible**; without one, "upgrade from the previous
   release" has nothing to check out, which is exactly where this plugin stands
   today.
5. Re-run A1 on the tag if the warning is coming off.
