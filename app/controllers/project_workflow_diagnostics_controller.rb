# frozen_string_literal: true

# The diagnostics page (ADR-002): which Redmine this is, whether anything the
# plugin copied from core has changed under it, whether the permissions it
# registered are the ones Redmine answers with, and where its patches are
# attached.
#
# Administrator-only, and it reads: there is no action on this controller that
# writes anything. `require_admin` rather than a permission, because every fact
# on the page is about the installation rather than about a project, and INV-7's
# question -- which project does this action authorize against -- has no
# meaningful answer here.
class ProjectWorkflowDiagnosticsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  # Rails' include_all_helpers is built from the host application's helper
  # paths and does not reach a plugin's app/helpers, so the page's own helper is
  # named here (the same reason Patches::IssuesControllerPatch gives).
  helper ProjectWorkflowDiagnosticsHelper
  before_action :require_admin

  def show
    @diagnostics = RedmineProjectWorkflows::Services::Diagnostics.new
  end
end
