# Things that surprise people

Everything here is a consequence of the design rather than a defect, and every
one of them has caught somebody out at least once.

## A project's own workflow replaces the generic one

It is never added to it. Once a project has taken a tracker and role over, the
generic rules for that combination do not apply at all — not as a fallback, and
not for the transitions the project did not mention. Adding one transition to a
project means its workflow is now the whole answer for that tracker and role.

This is why *Give own workflow* starts from a copy of the generic workflow.

## An own empty workflow permits nothing, and the Status field disappears

An own empty transitions workflow is a state you can reach deliberately, and it
means no issue in that project can change status for that role.

On the issue form that shows up as the **Status field not being there at all**,
with nothing to say why. That is Redmine's own rendering rather than something
this plugin draws: core shows the field only when at least one status is allowed,
and it adds the current status to that list only when something else is allowed
too. So the field disappears rather than showing a single dead option.

The *Workflow for this issue* panel is the only place that explains it. Redmine
behaves the same way without this plugin for any status with nothing leading out
of it.

## Nothing is inherited between projects

A subproject does not get its parent's workflow. It either has its own or follows
the generic one. Use the copy screen to apply one workflow to several projects.

## Roles resolve independently, and the result is a union

A user who holds two roles in a project may make any transition either role
permits. A project can override one role and follow the generic workflow for
another.

## An issue can end up on a status its project cannot leave

Move an issue into a project whose workflow does not use its current status, or
change a workflow under issues that are already open, and those issues sit on a
status with no transition out of it for that role.

Redmine does the same when an administrator edits the generic workflow;
per-project workflows just make it reachable more often. The comparison screen is
the fastest way to see it coming, and the workflow diagram names dead ends
outright.

## A save that changes nothing says so

Redmine reports *Successful update* for a matrix save where every control was
left at *(No change)*. This plugin tells you nothing was saved, because the same
message has to cover the case where the values you sent were not accepted.

## Deleting an issue status can leave a project's workflow empty

Redmine deletes every workflow rule naming a status you delete — the generic ones
and every project's. A project whose rules for a tracker and role *all* named that
status keeps its decision to run its own workflow and is left holding no rules at
all, which for transitions permits nothing.

The deletion screen reports how many project workflows that happened to, with a
link to them. It is a warning and not a repair: "runs an empty own workflow" and
"follows the generic workflow" are different states, and choosing between them is
yours.

## Copying a project copies its workflow

*Copy project* offers **Project workflows (N)** among *Members*, *Issues* and the
rest, ticked like all of them. A ticked box brings the project's own workflow
across, including an own empty one, for the trackers the copy actually has.
Untick it and the copy starts from the generic workflow.

Before 0.1.6 there was no box and no copying, so a copy quietly ran the generic
workflow — which in the ordinary case, a project given its own workflow to be
*stricter*, made the copy more permissive than the original with nothing said.

## Installing the plugin changes the generic workflow screens slightly

See [Living beside other plugins](compatibility.md#living-beside-other-plugins).
In short: the plugin has to route Redmine's own workflow writes through its own,
or a generic save would delete projects' rules along with the generic ones, and its
validation is slightly narrower than core's. In practice this only shows up for a
hand-built request.

## Uninstalling is a data change, not just a code change

Reversing the migrations deletes every project-specific rule and every record of
which projects decided to run their own workflow. See
[Uninstalling](operations.md#uninstalling).
