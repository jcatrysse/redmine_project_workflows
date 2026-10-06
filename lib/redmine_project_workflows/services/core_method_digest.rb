# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What core's own version of a method the plugin has replaced looks like on
    # *this* host, reduced to a digest.
    #
    # Why this exists (finding F03). The plugin does not extend eleven of core's
    # methods, it reimplements them: no `super` to fall through to, because
    # core's query carries no `project_id` predicate and running it would breach
    # INV-4 whatever was done with the answer afterwards. That is the right
    # design and it has a standing cost -- when core changes one of those bodies,
    # nothing notices. The plugin declares `requires_redmine version_or_higher:
    # '5.1'`, so 5.2, 6.0, 6.2, 7.1 and every future release install without
    # objection.
    #
    # This is not hypothetical. Hashing the copied bodies across 4.2, 5.0, 5.1,
    # 6.1 and 7.0 shows `Issue#new_statuses_allowed_to` changed twice, **both
    # times semantically**: 4.1 -> 4.2 replaced two open/closed checks, and
    # 5.0 -> 5.1 turned `user.admin ? Role.all : user.roles_for_project(project)`
    # into `roles_for_workflow(user)`, which adds a `consider_workflow?` filter.
    # A plugin carrying the 5.0 copy onto 5.1 would have offered status
    # transitions for roles that take no part in a workflow -- a silent
    # permission widening, with every one of the plugin's own specs still green,
    # because those specs assert the plugin's expected answers rather than
    # core's.
    #
    # Detection rather than declaration. **Narrowing `requires_redmine` to a
    # range is the wrong fix and is recorded as such:** core supports one, but
    # `lib/redmine/plugin.rb` raises `PluginRequirementError` and
    # `plugin_loader.rb` has no rescue around `run_initializer`, so on an
    # out-of-range Redmine the whole application refuses to boot until an
    # administrator deletes the plugin directory. That trades an uncertain
    # divergence for a certain outage.
    #
    # What this costs instead: nothing at runtime. The suite runs *inside* the
    # host Redmine checkout, so core's source is already on disk in all nine
    # cells. `UnboundMethod#super_method` reaches core's definition through the
    # prepend and `RubyVM::AbstractSyntaxTree.of` gives its line range. No gem,
    # no network, no CI change.
    class CoreMethodDigest
      # Every module of the plugin's that holds a copy of a core body, and the
      # class or module core defines that body on. Most are patch modules; one
      # is not, and is here for exactly the same reason -- a copy is a copy
      # wherever it is filed. The methods themselves are *discovered* from the
      # module rather than listed, so a new copy cannot be added without
      # appearing here, which is the property a hand-kept list would lose on its
      # first edit.
      #
      # The third element says where to look for the methods:
      #
      #   :instance   -- the patch carries instance methods of the named class.
      #   :singleton  -- the patch carries CLASS methods, and is prepended to the
      #                  singleton class. Missing until 2026-08-28 (F06 of
      #                  docs/review/findings/2026-08-28-claude-audit.md), and the
      #                  three it left out include
      #                  WorkflowTransition.replace_transitions and
      #                  WorkflowPermission.replace_permissions -- the two methods
      #                  INV-1's write isolation is routed through. The gate
      #                  covered nineteen methods and none of the three that
      #                  matter most.
      TARGETS = [
        ['Issue', 'RedmineProjectWorkflows::Patches::IssuePatch', :instance],
        ['Project', 'RedmineProjectWorkflows::Patches::ProjectPatch', :instance],
        # Not a patch module, and watched all the same: ProjectWorkflowMatrixHelper
        # holds the plugin's copies of core's two matrix cell helpers, and a copy
        # that leaves Patches must not leave the gate with it (ADR-003). Since
        # WorkflowsHelperPatch was deleted this is the only module of the
        # plugin's carrying a WorkflowsHelper body at all.
        ['WorkflowsHelper', 'ProjectWorkflowMatrixHelper', :instance],
        ['WorkflowsController', 'RedmineProjectWorkflows::Patches::WorkflowsControllerPatch', :instance],
        # Also not a patch module. ADR-003 moved the project dimension onto the
        # plugin's own administration controller, which carries copies of core's
        # seven workflow actions and of the four private finders under them --
        # and core's WorkflowsController is prepended by the entry above, so
        # reaching core's body for one of the four the patch still holds means
        # walking past that patch. See {core_source}.
        ['WorkflowsController', 'ProjectWorkflowRulesController', :instance],
        ['Role', 'RedmineProjectWorkflows::Patches::RolePatch', :instance],
        ['Tracker', 'RedmineProjectWorkflows::Patches::TrackerPatch', :instance],
        ['WorkflowTransition', 'RedmineProjectWorkflows::Patches::WorkflowTransitionPatch', :singleton],
        ['WorkflowPermission', 'RedmineProjectWorkflows::Patches::WorkflowPermissionPatch', :singleton],
        ['WorkflowRule', 'RedmineProjectWorkflows::Patches::WorkflowRulePatch', :singleton]
      ].freeze

      # Whether this Ruby can answer at all. CRuby only -- every supported
      # Redmine runs on it, but a spec must skip rather than fail elsewhere.
      def self.available?
        defined?(RubyVM::AbstractSyntaxTree) && RubyVM::AbstractSyntaxTree.respond_to?(:of)
      end

      # Everything this plugin's correctness rests on in core, digested:
      #
      #   * the methods it SHADOWS -- "Issue#new_statuses_allowed_to" for an
      #     instance method, "WorkflowTransition.replace_transitions" for a class
      #     one. A method the plugin merely adds has no core definition under it
      #     and is absent, which is the distinction finding F03 asked for: this
      #     reports the **copies and the delegates**, and nothing else.
      #   * the methods it CALLS but does not shadow -- the declared dependencies
      #     of the compatibility manifest. `Issue#roles_for_workflow` is called
      #     through `send` by three query services and is private in core, so it
      #     has no `super_method` and no visibility of its own to protect it. It
      #     was invisible to this gate until 2026-08-28 (ADR-002).
      #
      # One hash, because drift is drift: what an administrator needs to know is
      # that a body the plugin depends on is not the body it was tested against,
      # and which of the two reasons it is does not change what they do next.
      # +dependencies+ and +missing_dependencies+ separate them where the
      # distinction matters.
      def self.digests
        shadow_digests.merge(dependency_digests)
      end

      # The shadows alone: every method a patch module replaces.
      def self.shadow_digests
        TARGETS.each_with_object({}) do |(owner_name, patch_name, kind), memo|
          owner = patched_owner(owner_name, kind)
          patch = safe_constant(patch_name)
          next unless owner && patch

          shadowed_methods(patch).each do |method_name|
            digest = digest_for(owner, patch, method_name)
            memo[qualified_name(owner_name, method_name, kind)] = digest if digest
          end
        end
      end

      # The declared dependencies alone: core methods the plugin calls without
      # replacing. There is no patch in the chain, so the method the host holds
      # *is* core's own and no `super_method` step is wanted.
      def self.dependency_digests(names = Compatibility.dependencies.keys)
        names.each_with_object({}) do |name, memo|
          owner, method_name, kind = parse_qualified_name(name)
          owner = patched_owner(owner, kind)
          next unless owner

          digest = digest_for(owner, nil, method_name)
          memo[name] = digest if digest
        end
      end

      # The declared dependencies this host does not define at all. A harder
      # failure than drift and a different sentence to an administrator: a
      # changed body may still do what the plugin needs, while a method that has
      # gone raises NoMethodError on the first issue save.
      def self.missing_dependencies(names = Compatibility.dependencies.keys)
        names.reject do |name|
          owner_name, method_name, kind = parse_qualified_name(name)
          owner = patched_owner(owner_name, kind)
          owner && (owner.method_defined?(method_name) || owner.private_method_defined?(method_name))
        end
      end

      # The class the methods live on: the class itself for instance methods, its
      # singleton class for class methods -- which is where a patch carrying
      # class methods is prepended, and where core's own definition of
      # +replace_transitions+ is found.
      def self.patched_owner(owner_name, kind)
        owner = safe_constant(owner_name)
        return nil unless owner

        kind == :singleton ? owner.singleton_class : owner
      end
      private_class_method :patched_owner

      # Ruby's own notation, so that a name in the manifest reads the way it is
      # written everywhere else: Class#instance_method, Class.class_method.
      def self.qualified_name(owner_name, method_name, kind)
        "#{owner_name}#{kind == :singleton ? '.' : '#'}#{method_name}"
      end
      private_class_method :qualified_name

      def self.parse_qualified_name(name)
        owner, separator, method_name = name.rpartition(/[#.]/)
        [owner, method_name, separator == '.' ? :singleton : :instance]
      end
      private_class_method :parse_qualified_name

      # Public *and* private, because two of the copies are private in core --
      # Issue#workflow_rule_by_attribute among them, which is the method that
      # decides which fields are read-only or required. A first draft listed only
      # the public ones and silently covered thirteen of fifteen.
      def self.shadowed_methods(patch)
        (patch.instance_methods(false) + patch.private_instance_methods(false))
          .uniq.reject { |name| framework_generated?(name) }.sort
      end

      # Rails writes methods onto a class from its own macros, and a leading
      # underscore is the convention that says so: `layout 'admin'` defines
      # `_layout`, and so does core's own WorkflowsController, whose `_layout`
      # therefore looked to this gate like a body the plugin had copied -- with
      # the "core" definition pointing into the actionview gem. Nothing the
      # plugin copies out of Redmine is named that way; every one of the
      # twenty-six is an ordinary method somebody wrote in Redmine's own source.
      #
      # It only became reachable when ADR-003 put a *class* in TARGETS rather
      # than a module: a class carries the framework's generated methods and a
      # patch module carries only what somebody typed into it.
      def self.framework_generated?(name)
        name.to_s.start_with?('_')
      end
      private_class_method :framework_generated?

      # Core's body for one shadowed method, normalised and hashed. nil when the
      # plugin only adds the method, when core's definition is not in a file this
      # process can read, or when the AST is unavailable.
      def self.digest_for(owner, patch, method_name)
        source = core_source(owner, patch, method_name)
        source && Digest::SHA256.hexdigest(normalize(source))
      end

      # The text of core's definition, from the host's own checkout.
      #
      # **Three attachment styles, one question,** and the answer is never "how
      # is this module attached" but "whose definition is this". Where a patch is
      # prepended, the method the owner holds is the plugin's and core's is one
      # step up the chain. Where the module is in a controller's helper chain
      # instead -- `WorkflowsHelperPatch` and `ProjectWorkflowMatrixHelper` -- it
      # is not in the owner's ancestors at all, so `instance_method` already
      # answers with core's own. And where the module holds a copy of a body that
      # a *different* module of the plugin's also replaces -- ADR-003's
      # `ProjectWorkflowRulesController` against a `WorkflowsController` that
      # `WorkflowsControllerPatch` still prepends -- neither of the first two is
      # right, and asking about the module would digest the plugin's own body and
      # call it core's.
      #
      # So: walk down past every definition the plugin owns, whichever module it
      # is in, and take the first one that is not ours. That answers all three,
      # and it stops being an assumption about attachment. Walking off the end
      # means the plugin only *adds* the method and there is nothing of core's to
      # watch. A nil +patch+ is a declared dependency; the walk still applies,
      # because a dependency can sit under a patch of ours too.
      def self.core_source(owner, patch, method_name)
        core = owner.instance_method(method_name)
        core = core.super_method while core && plugin_definition?(core.owner, patch)
        return nil unless core

        file, = core.source_location
        return nil unless file && File.readable?(file)

        node = RubyVM::AbstractSyntaxTree.of(core)
        return nil unless node

        File.readlines(file)[(node.first_lineno - 1)..(node.last_lineno - 1)].join
      rescue NameError, ScriptError, ArgumentError
        nil
      end

      # Whether a definition is one of the plugin's rather than core's. The module
      # being asked about counts even when it is anonymous or lives outside the
      # plugin's namespace, which is how a plugin helper under `app/helpers`
      # (`ProjectWorkflowMatrixHelper`) is recognised.
      def self.plugin_definition?(mod, patch)
        mod == patch || mod.name.to_s.start_with?('RedmineProjectWorkflows')
      end
      private_class_method :plugin_definition?

      # Comments and whitespace out, so a re-indent or a reworded comment is not
      # reported as drift and a changed statement is. Deliberately crude: a
      # false positive here costs somebody five minutes of reading, and a false
      # negative is the thing this exists to prevent.
      #
      # `#` inside a string or a regexp would be over-stripped. That is accepted:
      # over-stripping can only merge two *different* bodies into one digest if
      # they differ exclusively after a `#` inside a literal, and the alternative
      # is a Ruby parser here.
      def self.normalize(source)
        source.gsub(/^\s*#.*$/, '').gsub(/\s+/, ' ').strip
      end

      def self.safe_constant(name)
        name.constantize
      rescue NameError
        nil
      end
      private_class_method :safe_constant
    end
  end
end
