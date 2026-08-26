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

    # Core marks an empty cell on the workflow summary page differently before
    # and after 6.0: 5.1 replaces the number with an +icon-not-ok+ span, while
    # 6.0 and later keep the number and colour it with +decoration-red+. The
    # plugin re-renders that cell -- it has to, to carry the project selection
    # into the link -- so it has to reproduce whichever of the two the host
    # uses.
    def project_workflows_summary_count_body(count)
      return count if project_workflows_svg_icons? || count.positive?

      content_tag(:span, nil, class: 'icon-only icon-not-ok')
    end

    def project_workflows_summary_count_class(count)
      'decoration-red' if project_workflows_svg_icons? && count.zero?
    end

    # A collapsible fieldset's legend, as core draws it above the author and
    # assignee halves of the transitions matrix. 5.1 puts the label in a legend
    # whose CSS class carries the arrow; 6.0 and later keep that class -- core
    # still sets it -- and put an SVG sprite in front of the label.
    def project_workflows_collapsible_legend(label, expanded)
      body =
        if project_workflows_svg_icons?
          sprite_icon(expanded ? 'angle-down' : 'angle-right', rtl: !expanded) + ' '.html_safe + label
        else
          label
        end
      content_tag(:legend, body, onclick: 'toggleFieldset(this);',
                                class: "icon icon-#{expanded ? 'expanded' : 'collapsed'}")
    end

    # The expander core puts in front of a group heading inside a table. Same
    # split as above: a non-breaking space on 5.1, an SVG sprite from 6.0.
    #
    # The space is the character rather than the &nbsp; entity core writes, so
    # that nothing has to be marked html_safe to render it.
    def project_workflows_row_group_expander
      body = project_workflows_svg_icons? ? sprite_icon('angle-down') : "\u00A0"
      content_tag(:span, body, class: 'expander icon icon-expanded', onclick: 'toggleRowGroup(this);')
    end

    # A link carrying one of core's icons, drawn the way the host draws icons:
    # an SVG sprite on 6.0 and later, a background image behind the CSS class on
    # 5.1. The class is set either way -- core keeps it on 7.0 too, for spacing.
    def project_workflows_icon_link(icon, label, path)
      body = project_workflows_svg_icons? ? sprite_icon(icon, label) : label
      link_to(body, path, class: "icon icon-#{icon}")
    end
  end
end
