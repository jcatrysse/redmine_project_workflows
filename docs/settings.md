# Settings

**Administration → Plugins → Project Workflows → Configure** has five settings:
three about writing a workflow, two about drawing one.

## Write limits

The first three are counted in **workflow rules** — one cell of a matrix, once
for each workflow the selection covers. They read as one scale.

| Setting | Default | What it does |
|---|---|---|
| Ask before a row or column action changes more than | 50 | One click can change a great many cells and you cannot see what it did without looking, so this one is small. `0` asks every time. |
| Ask before Save rewrites more than | 5,000 | Roughly 46 workflows of a six-status matrix. Save is a form you have just filled in, on a page that already says how many workflows one cell stands for, so it asks much later. Saving a single workflow never asks. |
| Refuse a matrix save that would rewrite more than | 200,000 | An administration save larger than this is refused before anything is written, and the message says how many rules it would have been. This is the guard against selecting every project, tracker and role at once. `0` means no limit. |

The refusal limit also bounds **Give own workflow**, which writes one rule per
rule in the source workflow per project, tracker and role. *Give own **empty**
workflow* copies nothing, so it is never refused whatever the selection.

## The diagram

| Setting | Default | What it does |
|---|---|---|
| Offer the workflow diagram | on | Turn it off and no link to the diagram is offered anywhere; the screen itself answers 404. Everything else is untouched. |
| Do not draw a workflow with more than | 2,000 arrows | Above this the page lists the workflow as a table instead. `0` means no limit. |

The arrow limit follows arrows rather than statuses, because placing the arrows
is what the drawing costs. Measured on Redmine 7.0 and PostgreSQL 16: a workflow
of 400 statuses and 800 arrows lays out in about 50 ms; one of 60 statuses in
which nearly every move is permitted (3,600 arrows) takes about 1.5 s. For scale,
Redmine's default workflow is five statuses and twenty-five arrows.

## How fast is a bulk save?

The plugin does not write one statement per rule the way Redmine's own workflow
save does. Measured on Redmine 7.0 and PostgreSQL 16, on modest development
hardware:

| What you did | What it cost |
|---|---|
| Save a matrix over 5 projects × 3 trackers × 3 roles (1,620 rules) | 30 statements, 0.22 s |
| The same 1,620 rules, one `save` per rule as Redmine does it | 6,480 statements, 5.03 s |
| Save a matrix over 50 projects (16,200 rules) | 400 statements, 2.4 s |
| *Empty this workflow* or *Return to the generic workflow* over 1,000 combinations | 5 and 6 statements, well under a second |

A save costs about eight statements per project and does not grow with the size
of the matrix. Throughput is roughly 27,000 rules a second, so the 200,000-rule
ceiling is about seven seconds of writing — which is where a front-end proxy
starts timing out.

**Give own workflow** was the one action still written a row at a time until
0.1.6. Giving 500 projects × 5 trackers × 8 roles a copy of a 30-rule generic
workflow, 600,000 rules in total:

| | Before | After |
|---|---|---|
| PostgreSQL 16 | 110 s, 60,042 statements | **18 s, 151 statements** |
| MariaDB 10.11 | 99 s, 60,048 statements | **14 s, 157 statements** |
| *Give own empty workflow*, same size | 60 s / 47 s | **3.9 s / 3.4 s** |

The row-at-a-time write was deliberate: it was how the plugin knew which
decisions *this* request had created, so two administrators pressing the button
at the same moment could not both be told they had created the same one. The
batched write keeps that guarantee differently — the action takes a small lock on
the workflow it is copying (one row per tracker and role, never one per project)
before it looks, so the second administrator waits and then sees what the first
did. That also closed a hole: the rules being copied used to be read under no
lock, so editing the generic workflow during a large copy gave the projects
copied early the old rules and the ones copied late the new ones.
