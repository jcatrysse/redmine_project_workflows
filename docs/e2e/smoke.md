# smoke

Run 2026-10-07T16:31:51.553Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](smoke-01.png) | admin | `/` | / (HTTP 200) |
| ![](smoke-02.png) | admin | `/projects/e2e-project` | /projects/e2e-project (HTTP 200) |
| ![](smoke-03.png) | admin | `/projects/e2e-project/issues` | /projects/e2e-project/issues (HTTP 200) |
| ![](smoke-04.png) | admin | `/issues/1` | /issues/1 (HTTP 200) |
| ![](smoke-05.png) | admin | `/projects/e2e-project/issues/new` | /projects/e2e-project/issues/new (HTTP 200) |
| ![](smoke-06.png) | admin | `/projects/e2e-project/settings` | /projects/e2e-project/settings (HTTP 200) |
| ![](smoke-07.png) | admin | `/my/page` | /my/page (HTTP 200) |
| ![](smoke-08.png) | admin | `/my/account` | /my/account (HTTP 200) |
| ![](smoke-09.png) | admin | `/admin` | /admin (HTTP 200) |
| ![](smoke-10.png) | admin | `/admin/plugins` | /admin/plugins (HTTP 200) |
| ![](smoke-11.png) | admin | `/settings/plugin/redmine_project_workflows` | /settings/plugin/redmine_project_workflows (HTTP 200) |
| ![](smoke-12.png) | admin | `/workflows/edit` | /workflows/edit (HTTP 200) |
| ![](smoke-13.png) | admin | `/workflows` | /workflows (HTTP 200) |
| ![](smoke-14.png) | admin | `/project_workflow_inventories` | /project_workflow_inventories (HTTP 200) |
| ![](smoke-15.png) | admin | `/projects/e2e-project/workflow/transitions` | /projects/e2e-project/workflow/transitions (HTTP 404) |
| ![](smoke-16.png) | admin | `/projects/e2e-project/workflow/permissions` | /projects/e2e-project/workflow/permissions (HTTP 404) |
| ![](smoke-17.png) | admin | `/projects/e2e-project/workflow/compare` | /projects/e2e-project/workflow/compare (HTTP 404) |
| ![](smoke-18.png) | admin | `/projects/e2e-project/workflow/graph` | /projects/e2e-project/workflow/graph (HTTP 404) |
| ![](smoke-19.png) | admin | `/issues/1/workflow_map` | /issues/1/workflow_map (HTTP 200) |
| ![](smoke-20.png) | admin | `/projects/e2e-project/workflow_map` | /projects/e2e-project/workflow_map (HTTP 404) |
| ![](smoke-21.png) | admin | `/project_workflow_diagnostics` | /project_workflow_diagnostics (HTTP 200) |
| ![](smoke-22.png) | admin | `/project_workflow_rules` | /project_workflow_rules (HTTP 200) |
| ![](smoke-23.png) | admin | `/project_workflow_rules/edit` | /project_workflow_rules/edit (HTTP 200) |
| ![](smoke-24.png) | admin | `/project_workflow_rules/permissions` | /project_workflow_rules/permissions (HTTP 200) |
| ![](smoke-25.png) | admin | `/project_workflow_rules/copy` | /project_workflow_rules/copy (HTTP 200) |
