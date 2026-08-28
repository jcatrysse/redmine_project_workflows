# frozen_string_literal: true

# The diagnostics page's own markup decisions, kept out of the view.
module ProjectWorkflowDiagnosticsHelper
  # The version split lives in one place for the whole plugin, and this page
  # needs it as much as the matrices do -- core's own tick is a bare
  # `icon-only icon-ok` span on 5.1 and an SVG sprite inside one from 6.0.
  include RedmineProjectWorkflows::VersionHelper

  # Core's checklist tick, exactly as app/views/admin/info.html.erb draws it on
  # the host under it: `icon-ok` or `icon-error`, with a sprite inside from 6.0.
  # The label is on the span rather than in it, so that a reader who cannot see
  # the colour is still told which of the two it is (G4).
  def project_workflow_diagnostics_tick(in_order)
    label = l(in_order ? :label_project_workflow_diagnostics_ok : :label_project_workflow_diagnostics_not_ok)
    icon = in_order ? 'checked' : 'warning'
    body = project_workflows_svg_icons? ? sprite_icon(icon) : ''.html_safe
    content_tag(:span, body, class: "icon-only icon-#{in_order ? 'ok' : 'error'}", title: label)
  end

  # The one sentence at the top of the page: which of ADR-002's three states
  # this host is in, in words rather than as a symbol.
  def project_workflow_diagnostics_state_sentence(manifest)
    case manifest.state
    when :verified
      l(:text_project_workflow_diagnostics_verified, version: manifest.host_minor)
    when :unmeasured
      l(:text_project_workflow_diagnostics_unmeasured, version: manifest.host_minor)
    when :unverified
      l(:text_project_workflow_diagnostics_unverified, version: manifest.host_minor,
                                                       newest: manifest.newest_verified_minor)
    else
      # Not `count:`. Interpolating a number under that name makes I18n look for
      # `one`/`other` subkeys and answer "translation missing" for a plain
      # string, in every language (docs/STATE.md's traps).
      l(:text_project_workflow_diagnostics_drifted, version: manifest.host_minor,
                                                    newest: manifest.newest_verified_minor,
                                                    methods: manifest.drift.size)
    end
  end

  # The CSS class for the box that sentence sits in. Redmine's own boxes, and
  # colour supporting the text rather than carrying it.
  def project_workflow_diagnostics_state_class(state)
    case state
    when :verified then 'nodata'
    when :unverified then 'notice'
    else 'warning' # drifted, and unmeasured -- neither is a reassurance
    end
  end

  def project_workflow_diagnostics_drift_status(status)
    l(:"label_project_workflow_diagnostics_#{status}")
  end
end
