# frozen_string_literal: true

module RedmineProjectWorkflows
  # The one place where a difference between the supported Redmine versions is
  # decided. Views call these wrappers instead of testing for host features
  # themselves, so that dropping or adding a version is a single edit here.
  #
  # Included into WorkflowsHelper through
  # RedmineProjectWorkflows::Patches::WorkflowsHelperPatch.
  module VersionHelper
    # Redmine 5.1 draws its icons from CSS classes. Redmine 6.0 replaced them
    # with SVG sprites and added the +sprite_icon+ helper, which 5.1 does not
    # have.
    def project_workflows_svg_icons?
      respond_to?(:sprite_icon)
    end

    # The multiselect expand/collapse control that core puts next to every
    # multiple-select workflow filter.
    #
    # Since 6.0 core renders <tt>sprite_icon('')</tt> inside the span as a
    # placeholder, and its +toggleMultiSelectIconInit()+ calls
    # <tt>updateSVGIcon($(this).find('svg')[0], iconType)</tt> for every
    # <tt>.toggle-multiselect</tt> on the page. A span without an <svg> makes
    # that argument +undefined+, +getElementsByTagName+ raises, and because the
    # call sits inside <tt>$(document).ready</tt> every initialisation
    # registered after it is skipped. On 5.1 the span is empty, as core's is.
    def project_workflows_toggle_multiselect_tag
      placeholder = project_workflows_svg_icons? ? sprite_icon('') : ''.html_safe
      content_tag(:span, placeholder, class: 'toggle-multiselect icon-only')
    end
  end
end
