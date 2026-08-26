# Reviewer prompt — full code review of `redmine_project_workflows`

Paste this into a fresh session. You are the **reviewer**: you read, you run,
you write one findings file. You do **not** change code, not even something
obviously trivial. `docs/review/README.md` explains why.

## 0. Branch and commit — before anything else

The execution environment mints a branch name per session and may hand you a
stale checkout. Do this first:

```bash
git fetch origin --prune
git checkout main && git pull --ff-only
git rev-parse --short HEAD    # put this in your findings file
```

Review the head of `main` unless you were told otherwise. Read `docs/STATE.md`
only **after** checking out — a stale STATE.md describes finished work and
reads perfectly plausibly.

## 1. What this software is

A Redmine plugin that gives individual projects their own issue workflows. It
adds a nullable `project_id` to Redmine's `workflows` table: `NULL` is a
generic rule, an id is a project rule. Reading `docs/design.md` first will save
you an hour; it is short.

The plugin is alpha. Finding that something is missing is less useful than
finding that something present is wrong.

## 2. Set yourself up so you can actually run things

You need a Redmine host. The repository builds one:

```bash
dev/setup.sh 5.1-stable postgresql 3.2      # or 6.1-stable / 7.0-stable, mysql
dev/run.sh .redmine/5.1-stable-postgresql
```

Read `dev/README.md` for the prerequisites (a database server, client headers,
a matching Ruby). A review that ran the suite is worth several that did not,
and the file has to say which you are.

Also clone the Redmine source you are reviewing against. When you are unsure
what core does, read core — do not guess. The workflow controller, helper and
views are byte-identical between 6.1 and 7.0; 5.1 differs.

## 3. Not review targets

- **INV-1..9 in `CLAUDE.md`.** A finding that proposes relaxing one is a
  `question` for Jan, never a fix.
- **Choices in `docs/DECISIONS.md`.** A scope replaces rather than merges;
  projects do not inherit from each other; transitions and field permissions
  scope separately; templates are out of scope. Re-litigating one of these is
  noise unless you have evidence the decision cannot work.
- **`spec/characterization/`.** Every example there passes and documents
  behaviour that is known to be wrong. Reporting them back as findings is
  duplicate work. Reporting that one of them has quietly started to describe
  something *different* is valuable.
- **Alpha-ness itself.** "Not production ready" is in the README.

## 4. What to review

Work these deliberately rather than reading top to bottom.

**Correctness.** The resolver and the two writers are where the money is. Does
the effective workflow match `docs/design.md` for every combination of scope
present/absent, rules present/absent, one role, several roles, several
projects selected at once? What happens at the boundaries — no trackers, no
roles, a role with `consider_workflow?` false, a project with no members?

**The three actions.** Enabling, returning to inheritance, and emptying must
stay three distinct database outcomes (INV-3). Try to find a path where two of
them coincide.

**Scope leakage.** Every query against `workflows` must carry a `project_id`
predicate (INV-4). Grep for the ones that do not. Then ask the harder version:
which of Redmine's *own* queries read that table without knowing about
projects, and what does the plugin do about each?

**Write isolation.** Can a generic save delete project rules, or the reverse
(INV-1)? Can request parameters reach `insert_all` without whitelisting
(INV-2)?

**Authorization.** Every controller action, every entry point. Once project
administrators can edit their own project, the question becomes: can a
parameter make one project's screen write another project's rules (INV-7)?

**Portability.** PostgreSQL and MySQL differ on ordering, on empty `IN ()`, on
what a non-numeric string casts to in an integer comparison. The suite runs on
both; the code should not depend on which.

**Version portability.** 5.1 has no SVG sprites; 6.0 and later do. Deface
anchors are exact text matches against core templates. An unmatched override
fails silently.

**Migrations.** Reversible? Does `VERSION=0` leave the host exactly as it was?
Does the reversibility check run before the suite, and do you understand why
that ordering matters?

**Performance.** The resolver sits on the path of every issue edit. Is it a
point lookup, or does it grow with the number of projects? Any N+1 in the
overview or the matrix?

**UI and UX.** Redmine idiom, no bespoke styling. Does every state say what it
is in words rather than only in colour? Are empty states sentences rather than
empty tables? Is the matrix operable from the keyboard?

**i18n.** Every user-visible string keyed, `en` and `nl` real, the other six
carrying the keys. English pasted into `nl` as if translated is a finding.

**Tests as code.** Do they assert behaviour or implementation? Would they fail
if the bug came back? Is there a test that passes for the wrong reason — the
one in this repo's history passed only because fixture issue 1 happened to be
a Bug.

**Documentation.** Does the README describe what the plugin does, including
that a scope *replaces*? Does `docs/design.md` still match the code?

## 5. Write the findings file

Copy `docs/review/findings/TEMPLATE.md` to
`docs/review/findings/YYYY-MM-DD-<reviewer>.md` and fill it in. One file per
run; never edit somebody else's.

Two things reviewers get wrong here:

- **State your scope, including what you did not cover.** An unstated gap reads
  as "clean".
- **Write the failure path.** "These inputs, this state, therefore this wrong
  outcome." If you cannot write that sentence, mark the finding `speculative`
  or `nit` rather than inflating it.

Then commit the file to `main` and verify the push landed. That is the only
thing a reviewer pushes.
