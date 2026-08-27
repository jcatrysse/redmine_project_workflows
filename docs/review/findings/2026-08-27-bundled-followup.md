# Review run — 2026-08-27 — follow-up on the bundled run

- **Reviewer:** Claude Code (Opus) — the same session that wrote
  `2026-08-27-bundled.md`, reviewing what the fixer did with it
- **Commit reviewed:** `9ce1921`
- **Ran the test suite:** **no** — this container has no Redmine host checkout.
  CI run **109** is green on all eleven jobs for exactly this commit. What was
  run locally is listed under "What was actually run"; two of the four findings
  below were established by executing something rather than by reading.
- **Pushed to:** **`claude/dev`**, as Jan chose for the previous run. See that
  file's header for what it changes.
- **Scope covered:** every `Resolution:` line of the twenty findings in
  `2026-08-27-bundled.md`, checked against the code rather than taken on trust;
  the 4,238 added lines read for new defects, with particular attention to the
  four new files and the three shipped files the fixer changed (two migrations
  and the writers); the mechanical gates re-run; the deleted spec examples
  checked for weakening.
- **Scope NOT covered:** the RSpec suite was not executed on any of the nine
  cells; no browser was driven; no MySQL or MariaDB server was available, so the
  `TIMESTAMP '…'` literal's acceptance on those two adapters rests on CI run 109
  having executed it rather than on my own observation.

## Summary

The fixer did the work. All twenty findings are `fixed` and the one `question`
was answered by Jan; nothing is left `open` in any findings file. I checked each
`Resolution:` line against the code rather than believing it, and in several
places the fix is better than the finding asked for.

Three are worth naming. **F03's drift gate** is a materially better design than
the one the finding sketched: the targets are *discovered* from the plugin's own
patch modules rather than listed, so a twelfth copied method cannot be added
without appearing in the gate, and it covers private methods — the fixer records
that a first draft listed only public ones and silently covered thirteen of
fifteen. I re-derived twelve of its eighteen digests from independently fetched
core sources with my own extractor: **twelve of twelve reproduce exactly**, and
the table's own claims about which Redmine minors differ match what the previous
run measured across five branches. **F01's fix** takes the lock as the first
statement in the transaction, computes the target set from the same method the
write uses so the two cannot diverge, and — the part I had flagged as the one
thing a fixer must re-establish — the comment records the quiet interleaving
reproduced from Rails with two connections. **F11** avoids the trap the finding
warned about: `generic_conditions` still intersects across the whole pair set,
and the comment names both wrong implementations with a spec for each.

Two of the four new findings below were introduced by the fixes themselves,
which is the ordinary cost of a large delta and the reason this run exists.
Neither is serious. The one worth reading is **N01**: F06 was filed because a
screen said too little about a partly refused save, and its fix now says too
much — the `rejected` count is multiplied by the number of populations in the
selection, so one bad value on an "all projects" save reports itself as five
hundred. A spec asserts the multiplied number, so the suite will not find it.

Nothing here is a blocker, nothing touches an invariant, and no gate was
weakened: RuboCop is clean on 104 files with **no** new `.rubocop_todo.yml`
entry, the JavaScript gate is green and now runs in CI, locale parity holds at
97 keys across eight files with matching placeholders, and the fifteen Deface
overrides are now counted by a gate that also checks the number written in
`CLAUDE.md` and `docs/design.md`. Four spec examples were deleted; I checked all
four and none is a weakening.

**Counts:** blocker 0 · major 0 · minor 2 · nit 2 · question 0

---

### F01 — The rejected-values count is multiplied by the selection, and the sentence names values

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** ux
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_patch.rb:246-253`,
  `lib/redmine_project_workflows/services/matrix_save_result.rb`,
  `spec/controllers/workflows_controller_spec.rb:548-556`,
  `config/locales/en.yml:63-65`
- **Invariant touched:** none
- **Introduced by:** the fix for F06 of `2026-08-27-bundled.md`

**What is wrong**

`MatrixSaveResult#rejected` is computed inside the writer, once per **population**
written. The administration actions sum a result per population:

```ruby
result = selected_project_ids.sum(result) do |project_id|
  TransitionWriter.replace_transitions_for_project_id(project_id, @trackers, @roles, transitions)
end
```

and `MatrixSaveResult#+` adds `rejected` along with `written` and `skipped`. The
payload is the same for every population, so the same rejected leaves are counted
once per population. The message it feeds is written in terms of the submission:

```yaml
notice_project_workflow_save_rejected_values:
  one:   "%{count} submitted value was not accepted and the rule it names was left unchanged."
  other: "%{count} submitted values were not accepted and the rules they name were left unchanged."
```

`written` and `skipped` are counts *of combinations*, so summing them is right.
`rejected` is a count *of submitted values*, and summing it is not.

**Why it matters**

An operator who submits one unacceptable value with *Generic* plus one project
selected is told two values were not accepted. With "all projects" selected on a
five-hundred-project installation, one unacceptable value reports itself as five
hundred, and the sentence claims five hundred rules were left unchanged.

That is the same defect class F06 was filed for — a screen saying something
untrue about what a save did. The fix for "the screen says too little" produced
"the screen says too much", in the same sentence.

It is minor because reaching it needs a hand-built request or an API client: no
screen can produce a value the whitelist refuses. That is exactly what F06 said
about itself, and it is why this is worth correcting rather than urgent.

**How I verified it**

Read the summation and `MatrixSaveResult#+`. The multiplication is not inferred —
`spec/controllers/workflows_controller_spec.rb:548-556` asserts it, and its own
comment names it:

```ruby
project_id: ['global', project.id.to_s],
permissions: { 'subject' => { old_status.id.to_s => 'readonly' } }   # one leaf
...
# one rejected leaf per project of the selection, and the selection is
# 'global' plus one project.
expect(flash[:warning]).to include(
  I18n.t(:notice_project_workflow_save_rejected_values, count: 2)
)
```

One submitted leaf, `count: 2` asserted. So the number is known and locked in,
and the suite cannot report this.

**Suggested direction**

Two honest options, and the choice is a copy decision as much as a code one.

Either make `rejected` mean what the sentence says — count it once for the
submission rather than once per population, which means computing it outside the
per-population loop, or dividing by the number of populations at the point the
result is summed. `MatrixSaveResult#+` summing all three members is the part that
makes the current shape invisible, so whichever way it goes, that method is where
a reader will look for the answer.

Or keep the number and change the sentence to name what it counts — refusals
across the selection rather than submitted values. That is cheaper in code and
more expensive in words: it needs a new phrasing in eight locale files, and
`CLAUDE.md`'s locale rule means all eight, so weigh it against the first option
rather than assuming it is the smaller change.

The spec at `:548-556` has to move either way, and its comment is the right place
to record which meaning was chosen — it is currently the only statement anywhere
of what the number counts.

**Resolution:** **fixed** by the first of the two options — the number now means
what the sentence already says. No locale file changed.

`MatrixSaveResult#+` adds `written` and `skipped` and takes the **maximum** of
`rejected`. That is the whole code change, and it is in the method the finding
named as the place a reader would look. Why a maximum rather than the two shapes
the finding sketched: computing `rejected` outside the per-population loop means
duplicating the whitelist outside the writer, which is the "one rule in two
places" mistake this repository has already had four findings about; and dividing
by the number of populations needs a denominator `#+` does not have and would
round. A maximum is exact for the shape that exists — both whitelists are built
from installation-wide lists (`IssueStatus` ids, `Tracker::CORE_FIELDS_ALL` plus
custom field ids, the two rule tables), so every population refuses the same
leaves — and it degrades honestly rather than absurdly if that ever stops being
true: the most values any one population refused, instead of a product.

The second option was **not** taken, and the reason is the one the finding asked
to be weighed rather than assumed: the eight-locale cost is real, but the
decisive part is that it makes the sentence describe an implementation detail
(how many populations a selection resolved into) to an operator who submitted one
value. It is logged for Jan under *Open — for Jan* in `docs/DECISIONS.md` with
both options, because the wording is his call and this one is reversible.

**Two existing assertions were wrong and have been corrected — that is a
different act from weakening a test, and `docs/review/README.md` rule 2 asks for
it to be said explicitly, because a diff stat cannot tell them apart.** Both
demanded `count: 2` where the request carried **one** unacceptable value:

* `spec/controllers/workflows_controller_spec.rb:554` — one submitted leaf,
  selection `'global'` plus one project. Its comment *explained* the 2 as "one
  rejected leaf per project of the selection", which is the defect written down
  as though it were the specification.
* `:1884` — one bad leaf, two projects selected. Now asserts `skipped: 1` and
  `rejected: 1` in the same example, which is the clearer statement: the two
  counts are deliberately different numbers, because one counts combinations and
  the other counts submitted values.

A third assertion at `:1854` (one project, one bad leaf, `count: 1`) was already
correct and is untouched — worth naming, because it is what made the other two
look plausible.

**Red on the old code, run rather than assumed:** six examples fail against the
summing `#+` — the two corrected assertions, one new controller example
(*reports one refused value once however many projects the selection holds*:
`'global'` plus three projects, one bad value, which reported **4**), and three
of the five in the new `spec/services/matrix_save_result_spec.rb`, where the
five-hundred-population case reports **500** against the required **1**. The
struct spec exists because the finding is right that `#+` is where the answer
lives: it is the only place the asymmetry between the three members can be
stated, and it needs no controller to state it.

---

### F02 — The matrix parameter guard raises on an array payload, which is the 500 it exists to prevent

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `lib/redmine_project_workflows/matrix_params.rb:45-50`,
  `lib/redmine_project_workflows/patches/workflows_controller_patch.rb` (its own
  `to_plain_hash`)
- **Invariant touched:** none
- **Source:** not claimed by any of the three source reviews; pre-existing, and
  moved unchanged into a new file by the fix for F14

**What is wrong**

`MatrixParams#to_plain_hash` exists to make a malformed matrix payload a
rejection rather than a crash. Its own comment says so:

> Guarded at every level, unlike core's own two loops: `transitions[1]=x`
> reaches those as a String and raises NoMethodError on `each_value`, which is
> a 500 rather than a rejection.

It handles nil, `ActionController::Parameters` and String. It does not handle an
**Array**:

```ruby
value.respond_to?(:to_h) ? value.to_h : {}
```

`Array` responds to `to_h`, and `['x'].to_h` raises
`TypeError: wrong element type String at 0 (expected array)`. So
`?permissions[]=x` — which Rails hands over as a plain `Array`, not as
`Parameters` — raises inside the guard, before any whitelist runs.

`Patches::WorkflowsControllerPatch#to_plain_hash` has the same shape
(`value.to_h.deep_dup`) and the same gap.

**Why it matters**

Four entry points: `PATCH` on the project's transitions and permissions
matrices, and the two administration saves. Each answers 500 for a request the
guard was written to reject politely. No form produces `permissions[]=`, so this
needs a hand-built request or an API client — the same reachability as F06 and
F14 of the previous run, and the same severity.

What makes it worth filing rather than shrugging at is that the guard's stated
purpose is precisely this, and the shape it misses is one Rails produces from an
ordinary query string. A comment claiming a class of input is handled, next to
code that handles all but one member of that class, is worse than no comment.

**How I verified it**

Reproduced the guard and the writers' new `leaf_count` in plain Ruby, without
Rails, over the five shapes Rails can hand to `params[:permissions]`:

```
?permissions=x        -> to_plain_hash OK  {}           leaf_count OK (0)
?permissions[1]=x     -> to_plain_hash OK  {"1"=>"x"}   leaf_count OK (1)
?permissions[]=x      -> to_plain_hash TypeError: wrong element type String at 0
?permissions[]=x&[]=y -> to_plain_hash TypeError: wrong element type String at 0
?permissions[1][]=x   -> to_plain_hash OK  {"1"=>["x"]} leaf_count OK (1)
```

Not driven through a running controller — that needs a Redmine host — so the
`TypeError` is established at the method rather than as an observed 500. The path
from `params[:permissions]` to this method carries no other conversion, which is
what makes the step short enough to be confident about.

**Suggested direction**

Whatever shape the fix takes, the property to hold is the one the comment already
claims: anything that is not a hash of hashes becomes an empty selection, and no
input reaches the writers as something they will raise on. An `Array` is the
member that is missing today; a `Hash` whose *keys* are not strings is worth
thinking about at the same time, because that is the other thing Rails can
produce and neither guard names it.

The two implementations have deliberately diverged once already (F14's
`Resolution:` says why), so this is two edits rather than one shared method — and
whichever property is chosen belongs in a spec, because the comment has now been
wrong for two runs without anything noticing.

**Resolution:** **fixed**, as two edits, and the property is now in four specs
rather than only in a comment.

Both guards now ask what the value **is** instead of what it answers to:

```ruby
return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

value.is_a?(Hash) ? value : {}          # ... .deep_dup in the patch's copy
```

That is the same question the loops one level down already ask (`is_a?(Hash)` per
level), so the guard is now consistent with itself. `respond_to?(:to_h)` is the
whole defect: `Array` answers it yes and then raises. The `nil` branch went with
it — `nil.is_a?(Hash)` is false, so it was doing nothing that the last line does
not — and the `deep_dup` stays in the administration copy, because
`strip_no_change` mutates what it is given with `reject!` and those parameters
belong to the request. Two edits, not one shared method, as the finding says: the
divergence F14 recorded is still real.

**Reproduced first.** The five shapes in the finding were re-run against both
guards as they stood, in plain Ruby: `?permissions[]=x` and `?permissions[]=x&[]=y`
raise `TypeError: wrong element type String at 0` in **both**, the other three
are fine, and a Hash with Integer or Symbol keys passes through unchanged. The
finding's table reproduces exactly.

**The tests assert the absence of the 500, not the presence of a branch** — which
the finding asked for and which is the difference between a gate and the
appearance of one. Four examples, one per entry point (project transitions,
project permissions, and the two administration saves), each asserting that an
Array payload produces the same redirect-and-write-nothing as the String payload
already covered. Rails re-raises in the test environment, so on the old code all
four fail with the `TypeError` itself rather than with a wrong status: run, and
that is what they did.

**The Hash-with-non-String-keys question is decided rather than left
unmentioned**, which is what F03 of this same run is about. Decision: **the
writers accept any key that answers `to_s` and `to_i`, and normalise what
survives the whitelist to Strings**; the controller guards do not coerce keys at
all. Reasoning, in the order it matters:

* Coercing in the guards would fix the shape only where it cannot arrive. Rails
  always hands over String keys, and the path that *can* carry others — core's
  own `WorkflowTransition.replace_transitions`, routed through the writer for
  INV-1 — does not pass through either guard.
* Symbol keys were not merely untested, they were a **live 500**: `:"1".to_s` is
  `"1"`, so they passed the whitelist, and then `submitted_pairs` called
  `Symbol#to_i`, which does not exist. Integer keys already worked, because every
  comparison downstream is against `.to_s` or `.to_i`.
* The normalisation goes in `sanitize_payload` in both writers, which is exactly
  where `TransitionWriter` already normalises the *rule* key one level deeper,
  for the same stated reason: what survives the whitelist is what everything
  below consumes. `PermissionWriter` normalises the field name too, because it
  travels into an `IN` list and into `insert_all`.

Three examples pin it (`spec/services/transition_writer_spec.rb`, *a payload
whose keys are not strings*): Integer keys write the expected rows, Symbol keys
write the expected rows, and the rejected count is unaffected by how the keys
were spelled. The Symbol one is **red on the old code** with
`NoMethodError: undefined method 'to_i' for an instance of Symbol`; the Integer
one passed before and is there so that the decision is stated in both
directions.

---

### F03 — F10's resolution dropped one of its own sub-items without saying so

- **Status:** open
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** docs
- **Where:** `docs/review/findings/2026-08-27-bundled.md`, F10's `Resolution:`;
  `lib/redmine_project_workflows/services/inventory_query.rb#deviating_triples`
- **Invariant touched:** none
- **Source:** V

**What is wrong**

F10's *Suggested direction* ended with a sub-item, introduced as "one thing
noticed while measuring, worth folding in": with no project filter applied,
`deviating_triples` renders every project id into the SQL text, so at three
thousand projects each page load ships a 15–20 KB `IN` list to be parsed and
planned. The finding noted that migration 004's cascading foreign keys make the
predicate unable to change the result set when the list is literally every
project, so dropping it would be behaviour-preserving, and that INV-4 governs
`workflows` rather than this table.

The `Resolution:` line answers the rest of F10 fully and in detail — the per-mode
comment, the measured figures, the rejected SQL rewrite, the deliberately
untaken packed key, two property examples. It does not mention this sub-item, and
the code still passes `project_id: ids(@projects)`.

**Why it matters**

Not for the `IN` list itself, which is small and which the finding did not call a
defect. It matters because a sub-item that is neither done nor declined is the
shape this repository has already been bitten by: `docs/review/README.md` says a
fixer leaves no finding at `open` without saying why, and `docs/STATE.md` records
G03 as the case where something sat unanswered because only part of the record
moved. A sub-item swallowed inside an otherwise thorough `Resolution:` is the
same failure at a smaller scale, and it is invisible precisely because the rest
of the answer is good.

**How I verified it**

Read F10's `Resolution:` line in full and grepped
`InventoryQuery#deviating_triples` for the predicate. The `Resolution:` mentions
the comment, the figures, the SQL rejection, the packed key and the two specs,
and nothing else.

**Suggested direction**

Answer it either way in F10's `Resolution:` line, in one sentence. If the `IN`
list is left as it is — which is defensible, and is what I would expect — say
that, so the next reader knows it was seen. The general habit is the point rather
than this instance: a `Resolution:` that answers four of five parts reads as
complete.

**Resolution:**

---

### F04 — One new log call reaches for the raw parameter where the validated one is in scope

- **Status:** open
- **Severity:** nit
- **Confidence:** confirmed
- **Category:** code-quality
- **Where:** `app/controllers/project_workflow_scopes_controller.rb:99`
- **Invariant touched:** none in effect; INV-2's habit
- **Introduced by:** the fix for F19 of `2026-08-27-bundled.md`

**What is wrong**

```ruby
RedmineProjectWorkflows::Services::WriteLog.record(
  'admin_scope_action',
  action_key: notice_key, rule_type: params[:rule_type], actor: User.current.id,
  ...
```

`@rule_type` is set and validated by `find_rule_type` at `:52-53`, which is a
`before_action` on every action in this controller and renders 404 for anything
outside `ProjectWorkflowScope::RULE_TYPES`. Every other use in the file — lines
28, 36, 44 and 112 — reads `@rule_type`. This one reads the parameter.
`MatrixReporting#log_rule_save`, the sibling call added by the same finding, uses
`@rule_type` correctly.

**Why it matters**

Nothing is wrong today, and it is worth saying so plainly rather than dressing it
up: the `before_action` guarantees the parameter is one of two literals by the
time `report` runs, and `WriteLog.format_value` would render anything longer than
32 characters or containing a space as `"String"` regardless, so there is no log
injection here even if the guard were removed.

It is filed because of what it costs later. This is the one line in the file that
depends on a `before_action` two screens away rather than on a value in scope,
and the habit it breaks is the one INV-2 is built on. The plugin has already had
findings whose whole content was one rule held in one of two places.

**How I verified it**

Read the controller. `grep -n '@rule_type'` gives lines 28, 36, 44, 52, 53 and
112, and line 99 is the parameter. Confirmed the `before_action` order at
`:15-17` so that the current safety is a fact rather than an assumption.

**Suggested direction**

`@rule_type`.

**Resolution:**

---

## What I verified of the twenty fixes

Not "read the Resolution and agreed". Per finding, what was actually checked:

| | How it was checked | Verdict |
| --- | --- | --- |
| F01 | The lock is the first statement inside the transaction at `workflows_controller_patch.rb`; `lock_scopes_for_copy` computes its combinations from `WorkflowRule.copy_pairs_for_project`, the same method the write uses, so lock and write cannot cover different sets; both rule types, no `rule_type` filter; ids sorted before the locked read, with the reason (batch ids only ascend within a batch). Three new examples, one of which asserts what the `FOR UPDATE` *returned* rather than the SQL text, because the ids travel as binds. The comment records the quiet interleaving reproduced from Rails with two connections — the one thing the finding said a fixer must re-establish | holds, and better specified than the finding |
| F02 | `docs/design.md`'s sentence now names the paths | holds |
| F03 | Re-derived twelve of the eighteen digests from core sources fetched independently from `5.1-stable` and `7.0-stable`, with my own extractor and their `normalize`: **12/12 exact**. The table's own claims check out — 18 methods, identical key sets, 6.1 ≡ 7.0, 5.1 differing in exactly the three controller actions, which matches what the previous run measured across five branches. Targets are discovered from the patch modules rather than listed; private methods included; an unknown Redmine minor is reported rather than failed; the failure message names the method, the host, both digests and core's `source_location`, and says explicitly that bumping the digest first is the one thing that makes the gate useless | holds, and materially better than the sketch |
| F04 | One statement, `IN` in place of the join plus subquery, `DISTINCT` gone, `combined_scope` untouched so every `project_id` predicate stays where it was | holds |
| F05 | `return unless User.current.admin?` at the top of the patched finder, with `user_setup`'s position established in the comment, and the F18 trap recorded as the reason not to reorder core's callbacks | holds |
| F06 | Third count on `MatrixSaveResult`, `SanitizedPayload` extended into both writers so the two cannot disagree, and a defensive `initialize` default with the reason (`nil.positive?` in a flash branch is a 500 on a successful save) | holds — see F01 above for what it introduced |
| F07 | A `javascript` job in `specs.yml`; ran the gate myself, 28 checks green in about a second | holds |
| F08 | `INV9_COUNTS` plus four examples: the count, distinct names, a plugin-id prefix, and — beyond what the finding asked — that the number written in `CLAUDE.md` and `docs/design.md` matches. A sixteenth override now raises `KeyError` on the word lookup rather than passing | holds, exceeds |
| F09 | `TIMESTAMP #{quote(quoted_date(Time.now.utc))}` in both places, and the migration comment corrected in both halves. Changing a shipped migration is argued rather than assumed. Its acceptance on MySQL and MariaDB rests on CI run 109, which re-runs migration 004 through `dev/check-backfill.sh` on six such cells | holds |
| F10 | Documentation and two property examples; the SQL rewrite recorded as rejected, the packed key named and deliberately untaken. That matches what the finding asked for — but see F03 above | holds, with one sub-item unanswered |
| F11 | `override_conditions` groups by `[tracker_id, sorted role ids]` with a project_id list; `generic_conditions` still intersects across the whole pair set, which is the trap the finding warned about, and the comment names *both* wrong implementations with an example for each — "confirmed to fail against the wrong implementation rather than argued about" | holds, trap avoided |
| F12 | `group :test` gone; the file now carries the reasoning, including why `deface` stays unpinned | holds |
| F13 | `permissions: contents: read` at workflow level; the Redmine commit echoed per cell; SHA pins deliberately declined with the rot argument | holds |
| F14 | `normalize_permissions_params` gone. Three of the four deleted spec examples belong to it, and the fixer **inverted rather than deleted** the two that asserted the transposed payload was accepted — so the suite now asserts it is refused, which is strictly more than before | holds |
| F15 | Focus moved to the region before the link is hidden, guarded on the link actually being visible and on `region.focus` existing; `tabindex="-1"` added; a case in the gate | holds |
| F16 | `for:` naming `selector_id`, label moved below the assignment | holds |
| F17 | `else` branches reusing the existing key, so no locale change | holds |
| F18 | The callback trap in `docs/STATE.md`; the INV-4 exception documented with both of its statements named, not just the DELETE | holds |
| F19 | `WriteLog` with a default-deny formatter (an unrecognised type renders as its class name), a 20-id cap, and `nil` rendered as `generic` because it is a real member of a project id list. All four call sites are outside the transaction | holds — see F04 above |
| F20 | `say_with_time` with `connection.delete` so the row count prints; the MySQL COPY-rebuild fact recorded in the migration and in `docs/design.md`; the README paragraph | holds |

**No test was weakened.** Fifty-five examples added, four deleted. Three of the
four belong to the code F14 removed and were replaced by a status-first
equivalent plus two inverted examples. The fourth — `'treats project_id=all as
all projects plus generic'` — was caught in the same hunk; its behaviour is
covered by the example thirty lines above it, which asserts that an `all`
selection reads statuses from the generic workflow *and* from two different
projects. That is a stronger assertion than the two instance variables the
deleted example checked. Worth one sentence in a future `Resolution:` that it
went deliberately, since nothing currently says so.

## What was actually run

On commit `9ce1921`, in this container:

- `rubocop` through `.github/lint/Gemfile` — **104 files, no offences**, and
  `git diff` shows **no change** to `.rubocop.yml` or `.rubocop_todo.yml`, so
  eight new files were absorbed without relaxing a cop or adding an exclusion
- `node dev/check-bulk-js.mjs` — green
- locale parity — **97 top-level keys across all eight files**, key sets
  identical to `en.yml`, and every `%{…}` placeholder set matching
- `grep -c 'Deface::Override.new'` — 15 across 12 files, names unique
- forbidden-constructs sweep over the new code: `insert_all` still only in the
  two writers; no `Thread.current`; the three new controller modules are
  all-private, and `plugin_conventions_spec.rb`'s `action_methods` example is the
  structural gate that would catch a public one
- twelve digests from `spec/upstream/core_method_digests.yml` re-derived from
  independently fetched core sources (see F03 above)
- the parameter guard reproduced in plain Ruby over five payload shapes (see F02
  above)
- `mcp__github__actions_list` — CI run **109**, `push`, `9ce1921`, conclusion
  **success**; the workflow now has three job groups (`lint`, `javascript`,
  `rspec`), so eleven jobs rather than ten

Not run: the RSpec suite, on any cell. CI run 109 on this commit is the evidence
in its place, and it includes the migration-reversibility, backfill and Zeitwerk
steps inside each of the nine rspec cells.
