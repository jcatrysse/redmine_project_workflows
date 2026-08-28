# Changelog

## 0.1.6

The workflow as a drawing.

### Added

- **A workflow diagram, per role.** A new **Workflow diagram** screen draws the
  whole of a project's status transitions for one tracker: a box per status, an
  arrow per permitted change, and Redmine's *New issue* starting point on the
  left. It is reached from the project's Workflow tab, from the top of both
  matrices, and from the panel on the issue form.

  It is per **role**, and that is the part no comparable screen elsewhere has.
  Redmine decides its workflow per tracker and per role, so the diagram offers
  every role the project screen already lists and starts on the roles the reader
  holds — "what may a developer actually do here" is a question it can answer
  directly.

  Underneath the picture, in words: the statuses **no permitted move can reach**
  from a new issue, the ones **nothing leads out of**, and the ones **the
  selected roles' rules never mention**. The first two are real defects in a
  workflow, and nothing else in Redmine reports them. A solid arrow is a change
  anyone with the role may make; a dashed one is a change only the author or the
  assignee may make.

  The same workflow is repeated as a table below the drawing. That is not an
  afterthought — no drawing is legible to a screen reader, and the table is also
  what Ctrl-F finds and what prints.

  The screen is behind the existing **View project workflow** permission: the
  diagram shows what *other* roles may do, which is project configuration rather
  than information about one issue. The panel on the issue form still needs no
  permission of its own.

  A project with its **own empty workflow** draws as the starting point alone,
  with the sentence saying that is a deliberate configuration and not a fault. A
  project that merely *inherits* a generic workflow nobody has filled in draws
  the same picture and says something different, because those are two different
  facts.

  No new dependency, no JavaScript and no build step: the drawing is inline SVG
  with the layout computed in Ruby, so the status names stay real text and a
  theme's colours carry through to it.

  **Redmine's own starting point is drawn too.** A stock Redmine ships a workflow
  with no rule at all in the *New issue* row, and it does not refuse to create
  issues because of it: when nothing says which status a new issue starts in,
  Redmine starts it on the tracker's default status. The diagram draws that as a
  dotted arrow and says in the legend that it is Redmine's fallback rather than a
  rule anyone wrote. Without it, a freshly installed Redmine reported *every*
  status as unreachable from a new issue, which is both wrong and the first thing
  a new reader would have seen.

  **A workflow with no progression says so rather than drawing spaghetti.**
  Redmine's default workflow lets every status become every other one, and a
  layered picture of that is a line between every pair of boxes — unreadable at
  six statuses, which is where the shipped configuration already is. The screen
  now says the workflow permits nearly every move and folds the drawing behind
  *Show the diagram anyway*. The three lists and the table stay where they are.

  **The statuses no new issue can reach** are laid out in columns of their own
  below the dotted line, instead of one flat row with every arrow between them
  bowed underneath it.

### Fixed

- **The workflow panel on the issue form no longer contradicts the status list
  beside it.** A reader holding two roles — one of them with a project workflow
  of its own that is deliberately empty, the other with rules — was told "no
  change of status is permitted" while the form offered a full list of statuses.
  The absolute sentence is now used only when *every* one of the reader's roles
  is in that state; otherwise the panel says that at least one of them is, which
  is what the diagram screen already said about the same situation.
- **The two workflow actions on the project's settings tab no longer read as one
  sentence.** *Give own workflow (copy of the generic one)* and *Give own empty
  workflow* sat side by side with no separator between them, and the second is
  the most consequential thing either screen offers. They are separated now, as
  are *Empty this workflow* and *Return to the generic workflow*.

## 0.1.5

The last finding left open from the review of 0.1.3 — the query behind the status
filter grew with the number of projects that have their own workflow, on a screen
ordinary users open rather than on an administration screen — and then the four
things a follow-up review of that work found. Two of those four were introduced
by the round of fixes before them, which is the ordinary cost of a large change
and the reason the follow-up review happened at all.

**No version of its own for the follow-up:** 0.1.5 has never been released — it
exists on the development branch, `main` still carries 0.0.3, and there is no tag
— so the four fixes belong in the entry for the version that is about to carry
them rather than in one that would suggest an upgrade step between two states
nobody has run.

### Fixed

- **A save that refuses some of the values it was sent no longer overstates how
  many.** The administration screens write a selection one population at a time
  (the generic workflow, then each selected project), and the count of refused
  values was added up once per population: submitting one unacceptable value with
  *all projects* selected on a five-hundred-project installation reported that
  five hundred values had been refused and five hundred rules left unchanged. The
  number now counts the request, which is what the sentence beside it has always
  claimed. Only reachable through a hand-built request or an API client — no
  screen can submit a value the plugin refuses — and the same is true of the next
  item.
- **A malformed matrix that arrives as a list no longer produces a server
  error.** The four save screens deliberately turn a payload that is not a matrix
  into "nothing was saved" rather than a crash, and that guard covered a plain
  text payload but not a list one: `transitions[]=x` answered 500 from inside the
  code written to prevent exactly that. It is now refused the same way, on all
  four.
- **The status filter and the status report on a project issue list no longer
  get slower as more subprojects take over their workflow.** The query that
  answers "which statuses does this project's workflow use" asked about each
  project separately, in one statement that grew a clause per project — around
  1,200 clauses and 90 KB of SQL for a tree of 300 subprojects with four
  trackers, on **every page view** of that project's issue list. Projects that
  have the same workflow arrangement, which is what copying a workflow to a whole
  subtree produces, are now asked about together, so the statement's size follows
  how many *different* arrangements exist rather than how many projects there
  are. No answer changes — the same statuses come back, and the same are left
  out.

### Internal

- The same query is behind the administration matrix with *all projects*
  selected, where the growth was already known and had been accepted. It is
  bounded there too now.
- Two spec assertions were **corrected**, not relaxed: both demanded the
  multiplied refusal count described above, and one of them explained that
  number in its own comment as though it were the requirement.
- The writers now settle what a payload whose keys are not text means — they
  accept it and normalise what survives their whitelist — which closes a
  server error reachable from the plugin's own internal write API, though not
  from any request.
- One log line reads the validated value in scope instead of the raw request
  parameter two screens away. Nothing behaved differently.
- Five tests, three of them written before the change and confirmed to pass on
  the old code, because the two plausible wrong ways to group projects together
  give wrong answers that no existing test would have caught. Each wrong version
  was implemented deliberately and confirmed to fail one of them.

## 0.1.4

Nineteen findings from a review that bundled three independent reviews of 0.1.3
and re-verified every claim in them. Two mattered: a concurrency defect on the
one write path the previous round's locking had missed, and the fact that nothing
would have noticed if Redmine changed a method this plugin has copied. The rest
are edges, documentation that had stopped being true, and two gates that existed
but were not being run.

**Upgrading:** no new migration, but two existing ones changed, so an
installation that has *not* yet migrated gets slightly different behaviour from
one that has — see *Changed* below. Nothing needs to be re-run.

### Fixed

- **Copying a workflow into a project can no longer leave rules behind that
  nothing will ever read.** The copy screen wrote the rules first and only then
  looked up whether the projects it had written into own their workflow, so a
  second request arriving in between — returning a project to the generic
  workflow, which an ordinary project member may do — could remove the record of
  ownership from underneath rules the copy had just written. Those rules then
  apply to nothing, nothing cleans them up, and the copy reported *Successful
  update*. Reproduced with two live database connections before it was fixed. The
  three other write paths were given this protection in 0.1.2; the copy is now
  the fourth.
- **A save that only partly worked says so.** If some of the values submitted
  were unacceptable and the rest were fine, the screen reported a plain success
  and said nothing at all about the part it had refused — while the whole point
  of refusing a value is that it leaves the rule it names alone *and tells you*.
  It now names how many values were not accepted, alongside reporting the save.
- **A save that carries no workflow at all no longer redirects in silence.** It
  says nothing was saved, which is what every other outcome on that screen has
  said since 0.1.3.
- **The two project selectors on the copy screen are readable by a screen
  reader.** Their labels were not associated with the selects, on the one screen
  where the two differ only in which is the source and which the target — and
  where getting them the wrong way round empties a workflow.
- **Keyboard focus is no longer lost when the undo link disappears.** Undoing a
  row or column action until there is nothing left to undo hid the link that held
  focus, which dropped focus to the top of the page.
- **The audit timestamps on MySQL and MariaDB are UTC.** They were the database
  server's local time, recorded as though they were UTC, so *Updated 3 hours ago*
  could be wrong by the server's offset — or in the future.
- **Administration screens do no work for a request that is about to be
  refused.** A visitor who is not logged in could make the workflow screens query
  every project on the installation before anybody had checked who was asking.
  Noise on a small Redmine; measurable on a large one, and repeatable at will.

### Added

- **Every workflow change is now recorded in the application log** — one line per
  save or scope action, with who, what and how many, and never the contents of
  the workflow itself. Previously the only record of a change that had rewritten
  thousands of rules was a flash message the operator had already navigated past.
- **The plugin now notices when Redmine changes underneath it.** It reimplements
  eighteen of Redmine's own methods, and until now nothing compared them against
  what Redmine actually ships — a change there is silent, and it has already
  happened twice to the method that decides which statuses a user may set. The
  test suite now checks all eighteen against the Redmine it is running in and
  fails, with the method named, when one of them changes.
- **Installation documentation for what the migrations do**, how large the table
  they touch actually is, and what to expect on MySQL and MariaDB.

### Changed

- **Two migrations build their timestamps differently**, which is the fix for the
  MySQL and MariaDB timestamps above. An installation that has already migrated
  keeps the values it wrote — they are not displayed anywhere, so this is
  invisible — and one migrating from now on gets correct ones.
- **One migration now prints the number of rows it deleted.** It removes workflow
  rules that name a project which no longer exists, and it printed no number at
  all. On an upgrade the number is always zero; being able to see the zero is the
  point.
- The plugin no longer adds its test dependencies to Redmine's own bundle. They
  were being installed into every installation of this plugin, production
  included.

### Internal

- The JavaScript that powers the row and column actions is now tested on every
  push rather than when somebody remembered to run it by hand.
- The count of view overrides the plugin relies on is asserted, so adding one
  without a test is now a deliberate act rather than a silent one.
- Documentation corrections where code and documentation disagreed: the locking
  rule, the cost of the inventory screen, what the migrations do to InnoDB, which
  of Redmine's methods are copied and which delegate, and one invariant's single
  deliberate exception.

## 0.1.3

Eight findings from an independent review of 0.1.2, plus three the review of
*this* work turned up in it. One of the eight matters on a large installation;
the rest are edges, and three of them are the same shape — a screen reporting
success for something it did not do.

**Upgrading:** no migration. Nothing in the database changes.

### Fixed

- **Saving the workflow with *All* projects selected no longer builds a URL out
  of every project id.** The Save form carried the selection as hidden fields
  and expanded *All* into an explicit list, so the redirect after Save named
  every project — roughly 11 KB of query string on an installation with 500 of
  them, which a default nginx rejects with a *414 Request-URI Too Large*: the
  save had worked and the administrator saw an error page. Below that size the
  failure was quieter, with every action link on the page carrying the same
  list. The keyword is now carried through as it stands, which is what the
  links beside it have always done.
- **A save that applied nothing no longer says *Successful update*.** The
  writers reported only what they had refused, and the screen worked out the
  rest by subtraction — which cannot tell "wrote everything" from "there was
  nothing left to write". A request whose values were all rejected is left
  deliberately without effect, and that is the whole point of rejecting them
  rather than clearing the rules they name; reporting it as applied undid half
  of it. The same held on a project's own workflow screen, and there also for a
  save that arrived just after somebody had returned the project to the generic
  workflow.
- **A copy that empties a workflow says so.** Copying into a project replaces
  the target's rules for both kinds of rule, so a source with, say, no status
  transitions leaves the target's own transitions workflow standing and empty —
  a state in which no issue in that project can change status for that role.
  It is a legitimate configuration and it is also how somebody deliberately
  empties a project, so the copy still does it; it now counts the combinations
  it left that way and names them.
- **A copy no longer marks workflows it did not touch as edited.** The audit
  columns behind *Updated by X, 2 minutes ago* were stamped across the whole
  selection, including a combination the copy had skipped because its source
  resolved to the target itself — a copy that moved nothing at all still
  changed the audit line of every combination it named.
- **A project's Workflow tab lists a role it does not offer, if that role
  already has a workflow of its own.** A system administrator can give a
  project its own workflow for *Non member* or *Anonymous*, and the last member
  holding an ordinary role can leave. Either way the project ran its own
  workflow for a role its own tab did not mention, with no way from that screen
  to see or undo it. Such a row is now listed and can be emptied or returned to
  the generic workflow; what it still is not offered is a *new* workflow of its
  own, which stays a system administrator's decision.

### Changed

- **The style checker now targets the oldest supported Rails, not the newest.**
  It was configured for Redmine 7.0's Rails, so it could demand a method that
  does not exist on Redmine 5.1 and pass the change — a gate that approves what
  the plugin cannot run is worse than no gate. Nothing in the plugin was
  affected; this closes the door.
- **The stale `.codex/` setup scripts are gone.** Nothing referred to them, they
  named a Redmine version the plugin no longer supports and omitted the newest,
  and they built the host somewhere `dev/run.sh` does not look. `dev/` is the
  supported path and `dev/README.md` now says so.

## 0.1.2

Two findings from a review of 0.1.1, both about what happens when two people
press a button at the same moment, and one of them about a rule this repository
states absolutely.

**Upgrading:** no migration. Nothing in the database changes.

### Fixed

- **Giving a project its own workflow reports what it created, and clears only
  that.** The scope rows were written with one statement for many rows, which
  skips a row that somebody else has just created — without saying so. Two
  administrators pressing *give own workflow* for the same tracker and role
  were therefore both told every scope had been created, and the second one
  went on to clear the rules the first one had just copied and copy the generic
  workflow over them. Each row is now written and validated on its own, and
  only the combinations actually created are counted, cleared and copied into.
- **A save no longer leaves rules behind that nothing will read.** Whether a
  project runs its own workflow for a tracker and role was read once and acted
  on afterwards, so a save running beside a *return to the generic workflow*
  could write its rules just after the scope they belong to had been deleted.
  Those rules stay in the table, the resolver ignores them — a project without
  a scope follows the generic workflow — and the save reports success over a
  change that never took effect. The two are now one decision: a save holds the
  scope rows it depends on until it has written, and returning to the generic
  workflow waits for it, or goes first and the save is refused and says so.

## 0.1.1

Two defects on the path "an administrator presses Save", found by a review of
0.1.0 and fixed here. Both could lose configuration silently, and one of them
changed what stock Redmine does.

**Upgrading:** no migration. Nothing in the database changes.

### Fixed

- **A cell left at *(No change)* is left alone.** One cell of the transitions
  matrix is three controls — the plain grid and the *author* and *assignee* grids
  below it — over two stored rows. The writer deleted on the cell rather than on
  the rule, so a single changed column deleted the rows of the other two: a
  selection where one workflow permitted a transition and another did not lost
  that transition on the next save, and reported "Successful update". Because the
  plugin routes Redmine's own `WorkflowTransition.replace_transitions` through
  that writer, this applied to the generic workflow as well as to a project's.
- **Saving a matrix no longer gives a project a workflow of its own.** The
  administration grid shows the rules the selection holds *itself*, so a project
  that inherits renders empty — and pressing Save wrote that emptiness back as an
  own **empty** workflow, in which no issue in the project can change status.
  Saving now writes only into combinations the project has already taken over,
  says how many it left alone, and the panel above the matrix says so before
  anything is pressed. The three state actions are the only way to take a
  workflow over, on every screen; the project's own tab already worked this way.
- A malformed matrix submission is rejected instead of raising, on the
  administration screens as it already was on a project's own.
- A matrix save is one transaction over the whole selection, so a failure part
  way through no longer leaves half of it rewritten.
- `Issue#workflow_rule_by_attribute` is private again, as it is in Redmine.
- The link the plugin adds to the issue form no longer raises if another plugin
  renders Redmine's issue form from a controller of its own.
- The threshold field on the settings screen refuses anything that is not a
  whole number, rather than accepting it and quietly using the default.
- Spanish, Portuguese and Polish used two or three different words for *tracker*
  and *role* between them; all three now use Redmine's own. Dutch said *dit
  tracker* where it meant *deze tracker*.

### Changed — wording

- The first of the three states is now **"Follows the generic workflow"**, in all
  eight languages, where it used to say *Inherits*. Redmine has no workflow
  inheritance and this plugin does not add any: a project either has taken a
  (tracker, role) over or it has not, and there is no inheritance between
  projects at all. "Inherits" suggested a project tree that does not exist, and
  it misled the plugin's own maintainer. The change is to the words on screen
  only — no setting, no data, no behaviour.

### Changed

- Giving many projects their own workflow at once no longer makes one database
  round trip per combination.

## 0.1.0

The release that makes "this project has its own workflow" a thing the database
records rather than something inferred from whether rows happen to exist. That
inference could not tell a deliberately empty workflow from an absent one, and
it silently returned a project to the generic workflow when its last rule was
deleted.

**Upgrading:** the migration backfills the new table, so a project that was
already working keeps working. Read
[Upgrading and uninstalling](README.md#upgrading-and-uninstalling) first —
especially before uninstalling, which removes every project-specific rule.

**Breaking:** the declared minimum is now Redmine **5.1**. It was 5.0, which
nothing had ever tested.

### The model

- A project's decision to run its own workflow is a row in
  `project_workflow_scopes`, separately for status transitions and for field
  permissions. Three states are now distinguishable and stay distinguishable:
  *inherits the generic workflow*, *own workflow*, *own empty workflow*.
- A project workflow **replaces** the generic one for the tracker and role it
  covers. There is no merging and there are no negative rules.
- No inheritance between projects: a subproject has its own workflow or uses the
  generic one.
- Every query against `workflows` names a `project_id`, so one project can never
  read another's rules — or have them counted into its totals.

### Correctness at Redmine's own seams

- `Project#rolled_up_statuses` is computed per project across the tree and
  unioned, with no role filter — which is what core does, and what stops the
  status filter coming back empty for a project without members.
- The two `Issue` call sites that asked a tracker which statuses it uses now ask
  the issue's own project's effective workflow. `Tracker#issue_status_ids` stays
  a global union on purpose.
- Copying a role or a tracker carries the project rules and their scopes along,
  so a copied role is a working copy.
- `rake redmine_project_workflows:deduplicate_workflow_rules` repairs a database
  that already has duplicate rules; the writers cannot produce new ones within a
  save.
- Redmine's own `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions` are routed through those writers, so a
  generic save can never delete a project's rules. **This changes the generic
  screens slightly even on an installation with no per-project workflow:** the
  writers whitelist `rule`, `field_name` and status ids against server-built
  lists, which is narrower than core, and a rejected entry is dropped before the
  delete so it leaves the rule it names alone rather than clearing it. The
  matrices cannot produce a rejected value; a hand-built request can.
- The copy screen rejects a source or target tracker or role that does not
  exist, instead of reading it as "any" or quietly dropping it. Redmine spells
  "copy from every tracker" and "that tracker is gone" the same way — both are
  `nil` — and drops an unknown target id from its query, so a stale form could
  copy from a source nobody chose, or report success for a selection it had only
  half applied. **This applies to the generic copy screen too,** with or without
  a per-project workflow: a selection that names something real still behaves
  exactly as before.
- The copy screen's **target project** control preselects *Generic*. A
  multiple-choice control with nothing selected sends nothing at all, so a copy
  form that showed no target project still copied into the generic workflow and
  reported success. What runs is now what the form shows. The **source** project
  control is unchanged: blank there already means the generic workflow and
  destroys nothing.

### Screens

- The **Summary** page counts the workflow you selected instead of mixing
  populations, and its links carry the selection.
- A **Workflow inventory**: one line per project, tracker and role, with the
  state in words, filters, and a link into each matrix.
- A **Workflow** tab in project settings, behind two new permissions
  (`view_project_workflow`, `manage_project_workflow`), so a project can run its
  own workflow without a system administrator. Every action authorizes against
  the project it acts on.
- **Row and column actions** on every transition matrix — Yes, No and
  *(No change)* — which reach the mixed-value cells Redmine's own check-all
  toggle cannot. With a count of what changed, an **Undo**, and a line saying
  nothing is written until Save.
- A **comparison** screen: which rules a project's own workflow has that the
  generic one does not, and the other way round, for one tracker and role.
- **Who last changed a workflow, and when**, on the project tab and in the
  inventory, kept separately from when the decision was taken.
- On the issue form, a **Workflow for this issue** panel beside Redmine's own
  status help icon: which of the three states governs the reader — per role,
  because a role can be overridden while the next inherits — what the workflow
  lets this issue move to, what leads into its current status, and, for anything
  the workflow permits but the status list is not offering, the reason. Redmine's
  own sentence where Redmine has one (an open subtask, a blocking issue, a closed
  parent), the plugin's where the reason is who the reader is. The link is there
  even when Redmine renders no status control at all — which an own empty
  workflow produces, and so does a plain generic workflow at any status with
  nothing leading out of it. Loaded when it is opened, so an ordinary issue edit
  costs nothing extra.
- Redmine's own status help icon on that form needed no change and is now
  covered by specs: the statuses it lists are the project's own effective
  workflow, never another project's. It is invisible until an administrator fills
  in **Administration → Issue statuses → Description**, which the README now
  says.

### Settings

- One setting: *Ask before a row or column action changes more than* — 50
  workflow rules by default, `0` to ask every time.

## 0.0.3

- Fix migration/index guards and controller 404 return safety.
- Add workflow project foreign key with cascade cleanup behavior.
- Improve i18n coverage and selector/role-resolution robustness.

## 0.0.2

- Refactor "Only display statuses that are used by this tracker" to only display statuses that are used by the selected project.

## 0.0.1

- Initial release.
