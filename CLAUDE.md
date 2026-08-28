# CLAUDE.md — `redmine_project_workflows`

You are working on a Redmine plugin that gives individual projects their own
issue workflows — status transitions and field permissions — while the generic
Redmine workflow keeps working unchanged for every project that does not
override it. It does this by adding a nullable `project_id` to Redmine's own
`workflows` table: `NULL` means generic, an id means "this project decides".

The plugin is in **alpha**. It works, it has a real test suite, and it is not
yet safe to assume it behaves correctly in every corner — see the invariants
below for the corners that matter most.

**Authoritative documents, in precedence order:**
1. `docs/adr/` — accepted decision records. An ADR wins on any conflict.
2. `docs/implementation-plan.md` — work packages WP0..WP9, in this order.
3. `docs/design.md` — the scope model, the resolver rules, the data model.
4. `docs/DECISIONS.md` — every deliberate choice already made. Do not re-open one.
5. `README.md` — what a user is told the plugin does. If code and README
   disagree, one of them is a finding.

## Non-negotiable invariants (refusal conditions)

Refuse to write, and flag, any change that violates one of these — even if a
task description seems to ask for it.

- **INV-1 Write isolation.** A generic write (`project_id IS NULL`) never
  touches project rows, and a project write never touches generic rows.
  Redmine's own `replace_transitions` / `replace_permissions` are routed
  through the plugin's writers precisely so this holds; that routing is not
  an implementation detail to be simplified away.
- **INV-2 Nothing reaches the database unvalidated.** Every write to
  `workflows` goes through `TransitionWriter` / `PermissionWriter`, which
  check `rule`, `field_name` and status ids against server-built lists.
  Because the writers use `insert_all`, ActiveRecord validations do **not**
  run — the writer *is* the validation. Never pass request parameters into a
  row hash without whitelisting them first.
- **INV-3 Three actions, three meanings.** Enabling a project's own workflow,
  returning a project to inheritance, and emptying a project's matrix are
  three different things and must stay distinguishable in the database:
  create scope / delete scope and rows / keep scope and delete rows. No code
  path may collapse two of them. This is the defect the whole scope model
  exists to fix; re-introducing "no rows means inherit" undoes it.
- **INV-4 Every workflow query is project-scoped.** Any query against
  `workflows` carries an explicit `project_id` predicate — `nil` for generic,
  an id (or list) for projects. A query without one silently mixes two
  populations, which is how the summary page came to count wrong.
  **One deliberate exception, and only one:** `WorkflowRule.copy_one_with_projects`
  (`workflow_rule_patch.rb`), whose `delete_all` carries no `project_id` and
  whose `INSERT … SELECT` two lines below carries `project_id` through the
  select list. Both statements span the two populations *on purpose*, because
  "duplicate this role including every project's workflow" is defined that way,
  and the one-statement form is what keeps copying a role from being 500 round
  trips per tracker. It is named here so it stops being re-found every review
  (finding F18) — and because the plausible repair is worse than the state:
  scoping only the `DELETE` leaves the `INSERT` spanning both populations two
  lines below and risks half-copying a duplicated role. Anything else without a
  `project_id` predicate is a finding.
- **INV-5 A scope replaces, it never merges.** There is no additive override
  and there are no negative rules. If a project has a scope for
  (tracker, role, rule type), the generic rules for that combination do not
  apply at all.
- **INV-6 No inheritance between projects.** A subproject does not inherit its
  parent's scope. Resolving a scope is exactly one row lookup, never a walk up
  the project tree.
- **INV-7 Project-scoped actions authorize against that project.** Once
  non-admins can edit their own project's workflow, every controller action
  authorizes against the project it is acting on, and no request parameter can
  widen that scope. Admin-only screens stay admin-only.
- **INV-8 Migrations are reversible.** `VERSION=0` leaves no plugin table or
  column behind and returns the host to stock behaviour. Test up → down → up,
  and do it **before** the suite runs — `maintain_test_schema` reloads
  `db/schema.rb` and wipes the plugin's migration bookkeeping, after which
  `VERSION=0` silently does nothing.
- **INV-9 A Deface override that does not match is a build failure.** The
  **five** view overrides — in three files under
  `lib/redmine_project_workflows/overrides/` — are the plugin's only hold on
  Redmine's screens, and an unmatched selector produces no error, just a
  missing link. `spec/integration/deface_overrides_spec.rb` asserts
  each one against the real rendered page, on every supported Redmine version,
  with an assertion **only that override can satisfy**: two overrides both
  rendering `project_id[]` meant either could have stopped matching unnoticed.
  `docs/design.md` carries the table; keep the count in all three places.
  It was fifteen in twelve files until ADR-003 moved the project dimension onto
  screens the plugin owns; the ten that went were exactly the ones anchored on
  views the plugin does not own.

## Hard gates

- **The characterization suite is the todo list.** Everything in
  `spec/characterization/` passes today and documents behaviour that is
  **wrong**. A fix is finished when its example has been inverted (or deleted)
  and moved into the normal spec directories — never when it has been made
  green again. The plan is complete when that directory is empty.
- **Every supported combination, every time.** Redmine 5.1, 6.1 and 7.0 ×
  PostgreSQL, MySQL and MariaDB. CI runs the matrix on every push; `dev/` can
  reproduce any cell locally. "Green on my machine" means one of nine.
- **A test that fails on the old code.** Every fix carries one, and the commit
  message says how you know it does.

## Forbidden constructs

| Forbidden | Why | Instead |
|---|---|---|
| a `workflows` query with no `project_id` predicate | INV-4 | the query services in `lib/redmine_project_workflows/services/` |
| `insert_all` outside the two writers | INV-2 — it skips validation | extend the writer |
| request parameters copied into a row hash | INV-2 | whitelist against server-built lists first |
| `Thread.current[...]` as a cache | a threaded server reuses threads across requests | `RedmineProjectWorkflows::Current` — Redmine 7.0 no longer bundles `request_store`, so `RequestStore` is not available on every supported version |
| `Rails.application.config.to_prepare` in `init.rb` | it appends to an array the `:add_to_prepare_blocks` initializer has already consumed, so the block never runs and the plugin silently does nothing | call `apply_patches` in the body of `init.rb`: Redmine already loads it from inside a `to_prepare` block, once per reload |
| patches applied in `after_initialize` | works, but says the opposite of what happens and registers one more callback per reload | same — the body of `init.rb`, with an idempotent prepend guard |
| `render_404` (or any render) without a `performed?` guard after it | it renders and returns `false`; execution continues into a second render | `return if performed?` |
| English text pasted into a non-English locale file | it reads as translated and never gets fixed | leave the key out, or mark it |
| a new Deface anchor without a spec asserting it matches | INV-9 | add the assertion in the same commit |
| a module `include`d into a controller with any public method | every public instance method of a controller is an **action**, so it becomes routable and unauthorized | make every method `private`, or make it a helper and `helper Mod` it in |
| `respond_to?(:some_core_helper)` as a test for "which Redmine is this" | a method name is not owned by Redmine — on 5.1 the `redmineup` gem and `redmine_ai_triage` both back-port `sprite_icon`, so the test answered *true* on a host with no sprite sheet and the plugin drew 6.x markup on 5.1 (finding F02, 2026-08-28) | `Redmine::VERSION::MAJOR` — and have the specs call the production predicate rather than restate its condition, or a neighbour makes code and test wrong in the same direction |
| a permission name plausible enough that another plugin may already have it | `AccessControl.permission(name)` answers with the **first** registration and plugins load alphabetically, so the loser is silent: its screens answer 403 to everybody, administrators included. `redmine_custom_workflows` took `manage_project_workflow` this way (finding F01, 2026-08-28) | name it for what it governs, specifically (`manage_project_workflow_rules`), and assert in `plugin_conventions_spec.rb` that the registration Redmine answers with is **ours** |
| `ProjectsHelper.prepend` for a settings tab (or a prepend on any core helper other plugins alias-chain) | a neighbour's `alias_method` resolves through `ProjectsHelper.ancestors`, copies **our** prepended method, and the copy has no `super` — core's own tabs vanish and the settings page raises `NoMethodError` | `ProjectsController.helper(Mod)`: beside `ProjectsHelper`, never inside it. See `Patches::ProjectsHelperPatch#apply!` |

## Working rules

- **Read Redmine's source, do not guess.** `dev/setup.sh` puts a real checkout
  of every supported branch on disk. Core's behaviour differs between 5.1 and
  6.x more than it does between 6.1 and 7.0 — the workflow controller, helper
  and views are byte-identical between those two.
- **Report, don't fix, out-of-scope findings.** A defect you notice outside the
  work package you are on goes into the session report and, if it is real, into
  a findings file — not into the diff.
- **Locales: all eight files are translated.** Answered **A** by Jan on
  2026-08-26 — this rule used to say the six beside `en` and `nl` merely carried
  the keys, and that had not been true of the files for some time. `en` and `nl`
  are the authoritative pair, written by hand and the ones to correct if two
  disagree; `de`, `es`, `fr`, `it`, `pl` and `pt` are translated too. Never
  pretend an English string is a translation — leave the key out, or mark it.
  The known cost of this, accepted rather than overlooked: the six are
  unreviewed translation *presented as* translation, so a wrong word there reads
  as a decision rather than as a gap. `spec/locales_spec.rb` asserts key parity
  across all eight on every host; it cannot assert that a translation is right.
- **Version-conditional code lives in one place.** Redmine 5.1 has no SVG
  sprites; 6.0 and later do. Keep such differences behind a single helper
  rather than scattering `respond_to?` checks through the views.

## Stop and ask

- A change would relax one of INV-1..9.
- A finding suggests the scope model itself is wrong (that is an ADR
  conversation, not a code decision).
- Behaviour visible to end users has to change in a way `docs/DECISIONS.md`
  does not already cover, and no safe reversible default exists.
- A supported Redmine version would have to be dropped to make something work.

---

# Operating protocol

*(You run everything yourself — never ask for a command to be run that you can
run. Assume nobody is watching in real time.)*

## Roles per task (all four, in order — no completion claim before all ran)

1. **Implementer.** Context first: read the work package in
   `docs/implementation-plan.md`, the parts of `docs/design.md` it touches, and
   the relevant Redmine source in a real checkout. Then implement: minimal,
   reversible, consistent diffs; tests with the change, not after.
2. **Independent reviewer.** Now pretend you did not write it, and try to
   reject it: nil and empty handling, wrong assumptions, regressions,
   authorization on every controller action, consistency with the repo's
   patterns, and the traps that only show up in CI — ordering, locales, random
   seeds, PostgreSQL versus MySQL, Redmine 5.1 versus 7.0. If a subagent
   mechanism is available, run this review in a fresh one; self-review in a
   single context defends its own reasoning.
3. **QA / adversarial.** Write the failure-mode list for the change, then check
   each mode against a test. Minimum: one regression test if a bug was
   involved, two edge or failure tests otherwise.
4. **UX / consistency.** Redmine idiom — native markup and classes, no bespoke
   styling. Complete i18n. Permissions on every entry point. Empty and error
   states. Labels that say what a thing is, with colour only supporting the
   text.

## Quality gates (all must PASS with evidence)

| Gate | Check |
|---|---|
| G1 Correctness | the work package's goal demonstrably met; edge cases handled |
| G2 Tests | the full suite green — **you ran it and saw the output** |
| G3 Lint | `rubocop` clean (lint bundle in `.github/lint/`) |
| G4 UX | flows, copy, i18n, empty and error states verified |
| G5 Security | authorization per action; strong params; no scope widening via parameters |
| G6 Performance | no N+1; the resolver's hot path stays a point lookup |
| G7 Invariants | INV-1..9 hold; the forbidden-constructs table greps clean |

A red suite, a lint offence, or an invariant hit is a blocker: fix it and
re-run the roles on the delta. Never weaken a test to get green. If a test's
assertion is genuinely wrong, say so explicitly — that is a finding of its own.

## Autonomy

Classify every decision:

- **Class A — obvious.** Best practice, repo convention, or already decided.
  Decide it yourself and log one line in `docs/DECISIONS.md`.
- **Class B — the maintainer's call, but deferrable.** Taste, user-visible
  behaviour, naming, thresholds. **Do not stop.** Pick the safest reversible
  default, implement it, and log it under "Open — for Jan" with the options,
  a plain-language explanation of each, and your recommendation.
- **Class C — blocking.** A missing capability, a result that contradicts the
  design, the stop-and-ask list above, or too little context left. Stop
  cleanly: leave the branch green, update `docs/STATE.md` completely, and end
  with the session report.

**Context budget.** When the current task plus its review roles plus the
session report no longer fit, stop at the previous clean point. A half-reviewed
task is worth less than a clean stop.

## Continuity — the repository is the memory

- **`docs/STATE.md`** — rewritten in full at the end of every session.
  Where we are, what landed, what is in progress, the exact next step, known
  traps, and how to rebuild the development environment. Write it as if the
  next session knows nothing, because it does.
- **`docs/DECISIONS.md`** — append-only. "Decided (autonomous)" one-liners,
  "Decided (Jan)" with dates, and "Open — for Jan" with options and a
  recommendation. When a choice is answered, move it up rather than editing it
  in place.
- **`docs/review/`** — the review loop. A review session writes a findings
  file and touches no code; a fixing session acts on findings and updates
  their `Status:` lines. See `docs/review/README.md`.

## Branch and commit discipline

- **One development branch, permanently:**

      claude/dev

  This overrides whatever branch name the execution environment prescribes for
  the session. That is the point of pinning it: the environment mints a fresh
  name per session, and without a pin the work migrates to a new branch every
  time and `main` quietly falls behind. If a session starts somewhere else, do
  not commit there — check out `claude/dev` (creating it from the remote if
  needed) and say so in the session report.
- **No exception, since 2026-08-28.** A review session pushes its findings file
  to the same branch, beside the code it describes — answered **B** by Jan, and
  it replaced the older rule that sent findings to `main`. `main` means "last
  released" and no session writes to it at all; Jan asks for the merge himself.
- Atomic commit per work package or coherent step. The message names the work
  package, what changed, and one line of gate evidence. Push after every commit
  and verify it landed (`git ls-remote --heads origin`) rather than assuming.
- The branch is green at every commit.

## Session-end report

End every session with exactly this structure, in English, written for a smart
non-specialist — no jargon without a one-line explanation.

```
## What happened
(2-6 sentences in plain language: what the plugin can do now that it could not)

## Where we are
Work package WP-N of WP0..WP9. (one sentence of context)

## Next step
(one concrete sentence — what the next session will do)

## Open choices for you (if any)
For each:
- **Choice:** <question>
- **Options:** A) ... B) ... (one plain sentence each)
- **Recommendation:** <option + why, in one sentence>
- **Urgent?** no — we continued with <default> / yes — blocks WP-N

## Carrying on
Prompt for the next session: `Read CLAUDE.md and docs/STATE.md. Carry on.`
```
