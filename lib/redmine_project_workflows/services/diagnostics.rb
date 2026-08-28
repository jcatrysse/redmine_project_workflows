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
      # itself. IssuesControllerPatch is the one: it puts
      # ProjectWorkflowMapsHelper into IssuesController's chain and nothing of
      # its own, because there is no core method to override -- only a helper
      # that a Deface override calls from a view IssuesController owns. Asking
      # for the patch module there reported a correctly applied patch as
      # missing, which is how this element came to exist.
      #
      # spec/services/diagnostics_spec.rb fails if a module under Patches is
      # missing from this list, so a new patch cannot be added without appearing
      # on this page.
      ATTACHMENTS = [
        ['IssuePatch', :prepend, %w[Issue]],
        ['IssuesControllerPatch', :helper, %w[IssuesController], 'ProjectWorkflowMapsHelper'],
        ['ProjectPatch', :prepend, %w[Project]],
        ['ProjectsHelperPatch', :helper, %w[ProjectsController]],
        ['RolePatch', :prepend, %w[Role]],
        ['TrackerPatch', :prepend, %w[Tracker]],
        ['WorkflowPermissionPatch', :singleton, %w[WorkflowPermission]],
        ['WorkflowRulePatch', :singleton, %w[WorkflowRule]],
        ['WorkflowTransitionPatch', :singleton, %w[WorkflowTransition]],
        ['WorkflowsControllerPatch', :prepend, %w[WorkflowsController]],
        ['WorkflowsHelperPatch', :helper, %w[WorkflowsController]]
      ].freeze

      # One line of the page each. Neither carries a sentence: the view builds
      # what an administrator reads out of locale keys, and what these hold is
      # the fact -- a permission name and how many plugins claim it, a module
      # name and where it is attached. English assembled in Ruby is English
      # nobody can translate.
      PermissionCheck = Struct.new(:name, :ok, :claimants, keyword_init: true)
      PatchCheck = Struct.new(:name, :ok, :style, :owners, :module_name, keyword_init: true)

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
      def ok?
        state != :drifted && permission_checks.all?(&:ok) && patch_checks.all?(&:ok)
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

      # The overrides this plugin has registered with Deface, as a LISTING and
      # deliberately not as a check.
      #
      # There is no honest pass/fail to be had here. A registered override is
      # not a *matching* one -- Deface reports nothing when a selector finds no
      # anchor, which is why INV-9 exists and why
      # spec/integration/deface_overrides_spec.rb asserts each one against a
      # rendered page on all nine cells -- and the other failure, an override
      # file that did not load, already stops the host from booting, because
      # `load_deface_overrides!` logs and re-raises. A green tick here would be
      # a claim about nothing.
      #
      # What it is for: an administrator comparing what this plugin says it
      # touches against a screen that looks wrong. ADR-003 reduces the list to
      # two, and at two a runtime anchor check becomes a line rather than a
      # suite.
      def registered_overrides
        ::Deface::Override.all.flat_map do |virtual_path, overrides|
          ours = overrides.keys.select { |name| name.to_s.start_with?(OVERRIDE_PREFIX) }
          ours.map { |name| [name.to_s, virtual_path.to_s] }
        end.sort
      rescue StandardError
        []
      end

      private

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
