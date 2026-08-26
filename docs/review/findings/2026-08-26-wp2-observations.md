# Findings — noticed while building WP2

- **Run:** 2026-08-26
- **Reviewed:** `claude/dev` at `c382b3f` (WP2)
- **How:** not a review session. These are defects noticed while working on WP2
  and outside its work package, recorded rather than fixed (`CLAUDE.md`,
  "Report, don't fix, out-of-scope findings").

---

### G01 — The workflow screens tell an anonymous visitor which project ids exist

- **Status:** open
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** security
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_patch.rb`,
  `find_trackers_roles_and_statuses_for_edit` and `load_project_options`;
  core `app/controllers/workflows_controller.rb:23-25`
- **Invariant touched:** INV-7 (at the edge of it — the screen itself stays
  admin-only)

**What is wrong**

Core declares its callbacks in this order:

```ruby
before_action :find_trackers_roles_and_statuses_for_edit, only: [:edit, :update, :permissions, :update_permissions]
before_action :require_admin
```

The plugin overrides the first one and calls `render_404` from it when a
`project_id[]` value does not resolve. Rendering from a `before_action` halts
the callback chain, so `require_admin` never runs and the 404 is returned to
whoever asked. The answer therefore depends on data the caller is not entitled
to see.

**Why it matters**

Measured on Redmine 7.0 (see below), `/workflows/edit`:

| Caller | `project_id[]=1` (exists) | `project_id[]=99999999` |
| --- | --- | --- |
| anonymous | 302 to `/login` | **404** |
| logged in, not an administrator | 403 | **404** |

So an unauthenticated visitor can enumerate project ids one request at a time,
and a logged-in non-administrator can too. It is a small leak — Redmine exposes
project *identifiers* freely and numeric ids in plenty of other places — and the
matrix itself is still unreachable without administrator rights, so nothing but
existence escapes. It is nonetheless the plugin's leak and not core's: core takes
no project parameter here, so it always answers 302 or 403.

`load_project_options` also runs `Project.sorted` for an unauthenticated
request, which is a query core would not have made.

**How I verified it**

A throwaway controller spec against the real 7.0 host, printing the status for
each of the four cases in the table; it produced exactly those four answers. The
spec was deleted again — recording a defect is not the same as pinning it.

**Suggested direction**

Do not render from the callback. Collect the invalid ids there, as it already
does, and let each action decide — every action that uses them already runs
after `require_admin`. Alternatively prepend a `require_admin` of the plugin's
own so that authorization is settled first, but that duplicates a core callback
and would have to be kept in step with it.

The natural home is **WP4**, which introduces the project settings tab and the
two permissions and therefore has to touch every authorization decision in this
controller anyway. Fixing it earlier is cheap; it is only listed here because it
is not WP2's.

**Resolution:** _(open — WP4)_

---
