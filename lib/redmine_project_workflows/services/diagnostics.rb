# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What this plugin looks like on the host it is actually running on, read
    # rather than assumed (ADR-002).
    #
    # Everything here answers a question whose wrong answer is **silent**, and
    # that is the whole selection rule. A plugin that fails loudly needs no
    # diagnostics page; these four do not fail at all:
    #
    #   * a Redmine nobody has tested this against boots cleanly and goes on
    #     using an obsolete copy of the method that decides which status
    #     transitions are permitted;
    #   * a neighbouring plugin that registers one of our permission names wins
    #     it -- `AccessControl.permission` answers with the first registration
    #     and plugins load alphabetically -- and our screens then answer 403 to
    #     everybody, administrators included, with nothing in any log
    #     (finding F01 of 2026-08-28-claude-plugin-compat-5.1);
    #   * a patch that stopped being applied leaves core's own behaviour in
    #     place, which looks like the plugin doing nothing rather than like an
    #     error;
    #   * a Deface override that did not load leaves a screen missing one
    #     control (INV-9).
    #
    # It reads. It changes nothing, and it is administrator-only.
    class Diagnostics
      # Every Deface override this plugin registers is named with this prefix --
      # a shared namespace, so a prefix, like the routes, the helpers and the
      # locale keys. It is what lets this page tell our overrides from the
      # forty-four other plugins' on a real host.
      OVERRIDE_PREFIX = 'redmine_project_workflows_'

      # Every module under Patches, what it attaches to, and how. Three styles,
      # and the difference matters -- two of them are deliberately *not*
      # prepends and the reasons are in the patches themselves:
      #
      #   :prepend   -- in the target's ancestors.
      #   :singleton -- in the target's singleton class's ancestors: the patch
      #                 replaces class methods.
      #   :helper    -- in a controller's helper chain, and nowhere near the core
      #                 helper module, because a neighbour's alias_method on that
      #                 module would copy our method and lose its super.
      #   :included  -- mixed into another patch rather than into core.
      #
      # A fourth element names the module to look for where it is not the patch
      # itself. Two patches are like that, and both for the same reason: they
      # put one of the plugin's helpers into a controller's chain and carry
      # nothing of their own, because there is no core method to override --
      # only a helper that a Deface override calls from a view core owns.
      # IssuesControllerPatch was the first, and asking for the patch module
      # there reported a correctly applied patch as missing, which is how this
      # element came to exist; WorkflowsControllerHelperPatch is the second
      # (ADR-003).
      #
      # spec/services/diagnostics_spec.rb fails if a module under Patches is
      # missing from this list, so a new patch cannot be added without appearing
      # on this page.
      ATTACHMENTS = [
        ['IssuePatch', :prepend, %w[Issue]],
        ['IssueStatusesControllerPatch', :prepend, %w[IssueStatusesController]],
        ['IssuesControllerPatch', :helper, %w[IssuesController], 'ProjectWorkflowMapsHelper'],
        ['ProjectPatch', :prepend, %w[Project]],
        ['ProjectsHelperPatch', :helper, %w[ProjectsController]],
        ['RolePatch', :prepend, %w[Role]],
        ['TrackerPatch', :prepend, %w[Tracker]],
        ['WorkflowPermissionPatch', :singleton, %w[WorkflowPermission]],
        ['WorkflowRulePatch', :singleton, %w[WorkflowRule]],
        ['WorkflowTransitionPatch', :singleton, %w[WorkflowTransition]],
        ['WorkflowsControllerHelperPatch', :helper, %w[WorkflowsController], 'ProjectWorkflowMatrixHelper'],
        ['WorkflowsControllerPatch', :prepend, %w[WorkflowsController]]
      ].freeze

      # One line of the page each. Neither carries a sentence: the view builds
      # what an administrator reads out of locale keys, and what these hold is
      # the fact -- a permission name and how many plugins claim it, a module
      # name and where it is attached. English assembled in Ruby is English
      # nobody can translate.
      PermissionCheck = Struct.new(:name, :ok, :claimants, keyword_init: true)
      PatchCheck = Struct.new(:name, :ok, :style, :owners, :module_name, keyword_init: true)
      AnchorCheck = Struct.new(:name, :virtual_path, :selector, :state, keyword_init: true)

      # The compatibility half is the manifest's own answer, unchanged: the page
      # asks the module that owns the facts rather than copying them here.
      delegate :state, :drift, to: :compatibility

      def compatibility
        Compatibility
      end

      # The adapter the host is configured with, which is the other half of the
      # nine-cell matrix and the first thing to ask about a defect that only one
      # installation sees. Read from the configuration rather than from a
      # checked-out connection: `ActiveRecord::Base.connection` is deprecated on
      # the Rails that Redmine 7.0 runs.
      def database
        ::ActiveRecord::Base.connection_db_config.adapter
      rescue StandardError
        nil
      end

      # Whether every question this page asks has the answer it should have.
      #
      # An anchor that could not be measured is deliberately not a failure: WP11
      # settled that a state saying "I could not measure" must not be reported
      # as either good news or bad. An anchor that was measured and did not
      # match is a failure, because that is exactly INV-9's silent one.
      def ok?
        state != :drifted && permission_checks.all?(&:ok) && patch_checks.all?(&:ok) &&
          anchor_checks.none? { |check| check.state == :unmatched }
      end

      # The permissions this plugin registered, found by their own actions
      # rather than by their names -- because the failure being looked for is
      # precisely a name that resolves to somebody else's registration, and a
      # search by name would find the impostor and report it as ours.
      def registered_permissions
        ::Redmine::AccessControl.permissions.select do |permission|
          permission.actions.any? { |action| action.to_s.start_with?('project_workflows/') }
        end
      end

      # Ours against the one Redmine answers with. Object identity, not a
      # comparison of action lists: two registrations of the same name are two
      # objects, and the question is which of them `AccessControl.permission`
      # hands to `User#allowed_to?`.
      def permission_checks
        registered_permissions.map do |permission|
          winner = ::Redmine::AccessControl.permission(permission.name)
          claimants = ::Redmine::AccessControl.permissions.count { |other| other.name == permission.name }
          PermissionCheck.new(name: permission.name.to_s, ok: winner.equal?(permission), claimants: claimants)
        end
      end

      def patch_checks
        ATTACHMENTS.map do |patch_name, style, owner_names, attached_name|
          module_name = attached_name || "RedmineProjectWorkflows::Patches::#{patch_name}"
          patch = constant(module_name)
          attached = patch ? owner_names.all? { |owner| attached?(patch, style, owner) } : false
          PatchCheck.new(name: patch_name, ok: attached, style: style, owners: owner_names,
                         module_name: attached_name)
        end
      end

      # The overrides this plugin has registered with Deface, and whether each
      # one's selector still finds its anchor in the view this host actually
      # ships (WP12 step 6).
      #
      # **This closes the one gap ADR-002's drift check explicitly does not
      # cover.** That check compares core method *bodies*; an override hangs on
      # core's *markup*, and Deface reports nothing at all when a selector finds
      # no anchor -- the screen simply comes out missing a control. INV-9 is the
      # rule, and `spec/integration/deface_overrides_spec.rb` is the gate, but a
      # gate on nine CI cells cannot speak about the Redmine an administrator is
      # actually running. This can, because ADR-003 took the count from fifteen
      # anchors to four: at fifteen this would have been a second test suite.
      #
      # How it asks. The template is read **from disk**, by the path Rails' own
      # resolver gives for the virtual path, rather than from
      # `ActionView::Template#source` -- Deface's own `encode!` rewrites that
      # string in place once a page has been rendered, so a source read there
      # would sometimes already carry the override and the question would answer
      # itself. Then Deface's own parser and the override's own matcher decide,
      # which is the same pair the applicator uses at render time; asking any
      # other way would be a second opinion about a selector rather than the
      # answer.
      #
      # Three states, not two. `:unmeasured` is for a template this process
      # cannot read or a Deface whose shape has moved under us, and it is
      # deliberately neither good news nor bad -- the same rule WP11 settled for
      # a Ruby that cannot read core's source. A green tick over an unread file
      # would be the exact failure this page exists to prevent.
      # Memoised: the view asks once, `ok?` asks again, and each answer costs a
      # file read and a Nokogiri parse per override. One instance is one request.
      def anchor_checks
        @anchor_checks ||= our_overrides.map do |name, virtual_path, override|
          AnchorCheck.new(name: name, virtual_path: virtual_path,
                          selector: safe_selector(override),
                          state: anchor_state(override, virtual_path))
        end
      end

      # What the page lists under "Redmine screens this plugin changes": name
      # and view, in a stable order.
      def registered_overrides
        our_overrides.map { |name, virtual_path, _override| [name, virtual_path] }
      end

      private

      # Ours, out of Deface's global registry -- which spans every installed
      # plugin, so the prefix is what tells our five from the forty-four other
      # plugins' on a real host.
      def our_overrides
        found = ::Deface::Override.all.flat_map do |virtual_path, overrides|
          overrides.filter_map do |name, override|
            [name.to_s, virtual_path.to_s, override] if name.to_s.start_with?(OVERRIDE_PREFIX)
          end
        end
        found.sort_by { |name, virtual_path, _override| [virtual_path, name] }
      rescue StandardError
        []
      end

      def anchor_state(override, virtual_path)
        source = template_source(virtual_path)
        return :unmeasured if source.nil?

        document = ::Deface::Parser.convert(source.dup)
        override.matcher.matches(document, false).empty? ? :unmatched : :matched
      rescue StandardError, ScriptError
        :unmeasured
      end

      def safe_selector(override)
        override.selector.to_s
      rescue StandardError
        nil
      end

      # The file Rails would render for a virtual path, read raw.
      #
      # Through the resolver rather than by globbing the view paths, because the
      # resolver is what decides which of several candidates wins -- a plugin
      # that overrides a core view by shipping its own copy is exactly the case
      # a glob would get wrong, and it is a case this plugin has to survive
      # rather than mis-report. The leading underscore comes off the name and is
      # passed as `partial:` instead, which is the shape the resolver expects.
      def template_source(virtual_path)
        prefix, _, name = virtual_path.rpartition('/')
        partial = name.start_with?('_')
        lookup = ::ActionView::LookupContext.new(::ApplicationController.view_paths)
        lookup.formats = [:html]
        template = lookup.find(partial ? name.delete_prefix('_') : name, [prefix], partial)
        identifier = template.identifier
        File.readable?(identifier) ? File.read(identifier) : nil
      rescue StandardError
        nil
      end

      def attached?(patch, style, owner_name)
        owner = constant(owner_name)
        return false unless owner

        # :prepend and :included ask the same question of different owners -- a
        # core class and one of the plugin's own patches -- and the answer is
        # the ancestors either way. They stay two styles because the page says
        # which it is, and a module mixed into a patch is not a change to
        # Redmine.
        case style
        when :prepend, :included then owner.ancestors.include?(patch)
        when :singleton then owner.singleton_class.ancestors.include?(patch)
        when :helper then owner._helpers.ancestors.include?(patch)
        else false
        end
      end

      def constant(name)
        name.constantize
      rescue NameError
        nil
      end
    end
  end
end
