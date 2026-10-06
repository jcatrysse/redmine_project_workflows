# ADR-002 — Compatibility is an object, not a set of comments

- **Status:** accepted, 2026-08-28 (answered by Jan the same day)
- **Supersedes:** nothing. It formalises what `requires_redmine`, the README's
  Compatibility section, `CoreMethodDigest`, `core_method_digests.yml`,
  `VersionHelper` and the CI matrix have each been saying separately.

## Context

The plugin does not extend twenty-two of Redmine's methods, it **reimplements**
them. There is no `super` to fall through to, because core's workflow queries
carry no `project_id` predicate and running one would breach INV-4 whatever was
done with the answer. That is the right design and `CoreMethodDigest` already
explains why narrowing `requires_redmine` to a range is the wrong repair: core
raises `PluginRequirementError` out of an initializer with no rescue, so an
out-of-range Redmine refuses to boot at all.

The standing cost is that a change under a copied body is silent. Three separate
reviews on 2026-08-28 arrived at the same place from different directions:

- A ChatGPT review commissioned by Jan named the policy gap directly:
  `requires_redmine version_or_higher: '5.1'` lets **every** future Redmine boot,
  while `spec/upstream/core_drift_spec.rb` **skips** rather than fails on a minor
  it has no digests for. An administrator can upgrade to 7.1 and get a clean boot
  over an obsolete copy of a method that decides which status transitions are
  permitted.
- The whole-stack compatibility run (`2026-08-28-claude-plugin-compat-5.1.md`,
  F02) showed that the plugin's *other* compatibility question is asked the wrong
  way as well. `project_workflows_svg_icons?` decides "does this host draw SVG
  icons?" by asking `respond_to?(:sprite_icon)` — and on a real Redmine 5.1 two
  neighbouring plugins define that method as a shim, so the plugin takes the
  Redmine 6 branch on a 5.1 host and the "no rules here" marker disappears from
  the workflow summary page. **A method name is not owned by Redmine.**
- The production-readiness audit (`2026-08-28-claude-audit.md`, F06) found that
  the digest table covers nineteen of the twenty-two shadows. The three it misses
  are the singleton-class ones, two of which — `WorkflowTransition.replace_transitions`
  and `WorkflowPermission.replace_permissions` — are the methods INV-1's entire
  routing rests on. A twenty-third dependency, `Issue#roles_for_workflow`, is
  called through `send` rather than shadowed and is therefore invisible to a gate
  built on `super_method`.

There is one more fact, and it is what makes a good answer possible rather than
merely a loud one. `CoreMethodDigest` was written for the test suite, but it does
not need one. Measured on a running Redmine 5.1 host, outside RSpec:

```
available?=true
digests computed at runtime: 19 in 34.5 ms
```

The plugin can therefore ask, on a host it has never been tested against,
**whether anything it copied has actually changed.**

## Decision

**One compatibility manifest owns every version fact, and the plugin answers
three states instead of two.**

1. **A single manifest** — `lib/redmine_project_workflows/compatibility.rb` plus
   its data — carries: the verified Redmine minors, the Ruby and Rails ranges,
   the supported databases, the core-method digests per minor, and the declared
   private-API dependencies. Everything that needs a version fact reads it:
   `VersionHelper`, the drift spec, the conventions spec, the diagnostics page,
   the README's generated Compatibility section.

2. **No feature probing, ever.** A version question is answered from
   `Redmine::VERSION::MAJOR` and `::MINOR` through the manifest, never by asking
   whether a method exists. F02 of the whole-stack run is the reason, and the
   rule is general: `respond_to?` asks about the installation, not about Redmine.

3. **Three states, not two.** On boot the plugin resolves one of:

   - **verified** — the running minor is in the manifest. Nothing happens, and
     no digest work is done at all, so a verified host pays nothing.
   - **unverified, no drift** — the minor is unknown, but every digest matches
     the newest verified set. One `Rails.logger.info` and a line on the
     diagnostics page. No banner.
   - **unverified, drift** — the minor is unknown and one or more digests
     differ. An administrator-visible warning naming **which** methods changed
     and where core defines them, plus the same line in the log.

   The digests are computed lazily and only in the second and third cases.

4. **A warning, never a refusal.** An unverified host is not blocked from
   writing. The ChatGPT review proposed blocking writes until an administrator
   acknowledges the version; that is a worse failure mode than the problem — it
   bricks an installation on an upgrade the administrator may have had no choice
   about, and it disables precisely the screens where they would put it right.
   Answered by Jan on 2026-08-28: warn.

5. **CI fails where runtime warns.** An unknown minor under test is a failure of
   the compatibility job, not a skip. The current `skip` is what let "we test
   three minors" and "we boot on all of them" drift apart in the first place.

6. **The gate watches everything it depends on.** `CoreMethodDigest::TARGETS`
   extends to singleton classes so discovery stays discovery, and declared
   private-API dependencies — `Issue#roles_for_workflow` today — get an entry of
   their own, because a method that is called rather than shadowed has no
   `super_method` to digest and needs a different kind of check.

## What the drift check does and does not prove

Stated here rather than in a comment, because the whole value of state two is
that somebody trusts it.

**It proves:** every method body this plugin copied is byte-identical, after
comments and whitespace are normalised away, to the body on a Redmine the plugin
was tested against.

**It does not prove:**

- that core still *calls* those methods the same way, or with the same
  arguments;
- that private helpers those bodies call are unchanged — which is exactly why
  the declared-dependency entries exist, and why the list of them is part of
  the manifest rather than folk knowledge;
- that the Deface anchors still match; that is a separate check, and ADR-003
  makes it cheap by reducing the anchors from fifteen to two;
- that core's own `workflows` schema is unchanged.

So the wording an administrator sees is **"no drift detected in what this plugin
copied"** — strong evidence, offered as evidence. Not "safe".

## Alternatives considered

- **Narrow `requires_redmine` to a range.** Rejected before this ADR and
  recorded in `CoreMethodDigest`'s own comment: core turns an out-of-range
  version into a boot failure with no rescue, which trades an uncertain
  divergence for a certain outage.
- **Block writes on an unverified host.** The ChatGPT review's proposal.
  Rejected: see decision 4.
- **Keep probing for features but probe more carefully.** Rejected. F02 shows the
  failure is not that the probe was sloppy but that the namespace is shared. Any
  probe can be answered by a neighbour.
- **Digest at boot on every host.** Rejected: 34.5 ms on every worker start for a
  question a verified host already knows the answer to. Lazily, and only when the
  version is unknown.

## Consequences

- A new Redmine minor becomes a **three-minute** decision instead of an audit: run
  the plugin on it, read the drift report, and either add a manifest entry or
  read one diff. That is the property this plugin needs to survive many
  generations of Redmine.
- One more thing to keep current. The manifest is now the single place that can
  be wrong, which is the point — today there are seven.
- The diagnostics page gains a second job beyond compatibility: the whole-stack
  run's F01 showed that a neighbouring plugin can capture one of our permission
  names and silently 403 every write. A boot-time check that each permission we
  register still resolves to *our* action list belongs on the same page, for the
  same reason.
- `spec/plugin_conventions_spec.rb` gains the assertion that no version question
  is answered by `respond_to?`.
