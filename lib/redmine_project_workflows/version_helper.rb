# frozen_string_literal: true

module RedmineProjectWorkflows
  # The one place where a difference between the supported Redmine versions is
  # decided. Views call these wrappers instead of testing for host features
  # themselves, so that dropping or adding a version is a single edit here.
  #
  # Included into WorkflowsHelper through
  # RedmineProjectWorkflows::Patches::WorkflowsHelperPatch.
  module VersionHelper
    # True from Redmine 6.0 on, where +IconsHelper#sprite_icon+ and
    # +app/assets/images/icons.svg+ arrived and the +icon icon-add+ CSS classes
    # stopped carrying a picture. 5.1 answers false and draws its icons from
    # those classes.
    #
    # The version itself lives in the compatibility manifest, with the verified
    # minors and the core digests, because it is the same kind of fact and
    # ADR-002 gives all of them one home. This method stays where the views
    # reach for it.
    #
    # **The series, deliberately, and not +respond_to?(:sprite_icon)+.** That is
    # what this asked until 2026-08-28, and on Redmine 5.1 it answers *true*:
    # the +redmineup+ gem back-ports a +sprite_icon+ onto +ApplicationHelper+
    # for every RedmineUP plugin, and +redmine_ai_triage+ back-ports another.
    # The plugin then drew Redmine 6 markup on a Redmine 5 host, and the
    # +icon-not-ok+ marker that says "this combination has no rules" disappeared
    # from the workflow summary page in favour of an unstyled +0+ carrying a
    # +decoration-red+ class 5.1's stylesheet does not define. Measured on a
    # 45-plugin host (finding F02 of
    # +docs/review/findings/2026-08-28-claude-plugin-compat-5.1.md+).
    #
    # A method name is not owned by Redmine; a version number is. Ask the fact.
    def self.core_sprite_icons?
      Compatibility.core_sprite_icons?
    end

    # The instance-side wrapper the views and the specs both go through, so that
    # nothing restates the condition and no two statements of it can drift.
    def project_workflows_svg_icons?
      VersionHelper.core_sprite_icons?
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

    # The body of a link or a button carrying one of core's icons, drawn the way
    # the host draws icons: an SVG sprite on 6.0 and later, the label alone
    # behind the CSS class on 5.1.
    def project_workflows_icon_body(icon, label)
      project_workflows_svg_icons? ? sprite_icon(icon, label) : label
    end

    # A link carrying one of core's icons, drawn the way the host draws icons:
    # an SVG sprite on 6.0 and later, a background image behind the CSS class on
    # 5.1. The class is set either way -- core keeps it on 7.0 too, for spacing.
    def project_workflows_icon_link(icon, label, path)
      link_to(project_workflows_icon_body(icon, label), path, class: "icon icon-#{icon}")
    end
  end
end
