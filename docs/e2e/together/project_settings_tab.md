# project_settings_tab

Run 2026-10-07T16:28:02.827Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](project_settings_tab-manager-inherits.png) | manager | `/projects/e2e-project/settings?tab=project_workflows` | Manager: the Workflow tab, every combination follows the generic workflow, actions offered |
| ![](project_settings_tab-manager-own-copy.png) | manager | `/projects/e2e-project/settings/project_workflows` | Manager: Bug x E2E full transitions taken over as a copy; the cell offers Empty and Return |
| ![](project_settings_tab-manager-own-empty.png) | manager | `/projects/e2e-project/settings/project_workflows` | Manager: after Empty the combination is an own EMPTY workflow, distinct from inheriting |
| ![](project_settings_tab-manager-perm-empty.png) | manager | `/projects/e2e-project/settings/project_workflows` | Manager: field permissions given an own empty workflow directly |
| ![](project_settings_tab-viewer-readonly.png) | viewer | `/projects/e2e-project/settings?tab=project_workflows` | Viewer (view permission only): the tab is shown read-only, no actions |
| ![](project_settings_tab-reporter-no-settings.png) | reporter | `/projects/e2e-project/settings` | Reporter (no plugin permission, no project settings): project settings refused |
| ![](project_settings_tab-reporter-matrix-403.png) | reporter | `/projects/e2e-project/workflow/transitions?tracker_id=1&role_id=6` | Reporter: the project matrix URL answers 403 |
| ![](project_settings_tab-outsider-private-403.png) | outsider | `/projects/e2e-private/workflow/transitions?tracker_id=1&role_id=6` | Outsider: the private project and its workflow are refused |
| ![](project_settings_tab-admin-private-tab.png) | admin | `/projects/e2e-private/settings?tab=project_workflows` | Admin: the Workflow tab of the private project |
