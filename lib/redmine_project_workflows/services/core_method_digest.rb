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
      # The prepended modules whose methods shadow a core method, and the class
      # or module each is prepended to. Discovered from the plugin rather than
      # listed, so a twelfth copy cannot be added without appearing here -- which
      # is the property a hand-kept list of eleven would lose on its first edit.
      TARGETS = [
        ['Issue', 'RedmineProjectWorkflows::Patches::IssuePatch'],
        ['Project', 'RedmineProjectWorkflows::Patches::ProjectPatch'],
        ['WorkflowsHelper', 'RedmineProjectWorkflows::Patches::WorkflowsHelperPatch'],
        ['WorkflowsController', 'RedmineProjectWorkflows::Patches::WorkflowsControllerPatch'],
        ['Role', 'RedmineProjectWorkflows::Patches::RolePatch'],
        ['Tracker', 'RedmineProjectWorkflows::Patches::TrackerPatch']
      ].freeze

      # Whether this Ruby can answer at all. CRuby only -- every supported
      # Redmine runs on it, but a spec must skip rather than fail elsewhere.
      def self.available?
        defined?(RubyVM::AbstractSyntaxTree) && RubyVM::AbstractSyntaxTree.respond_to?(:of)
      end

      # "<class>#<method>" => digest of core's body, for every method the plugin
      # shadows on this host. A method the plugin adds rather than replaces has
      # no `super_method` and is absent, which is the distinction the finding
      # asked for: this reports the **copies and the delegates**, and nothing the
      # plugin merely adds.
      def self.digests
        TARGETS.each_with_object({}) do |(owner_name, patch_name), memo|
          owner = safe_constant(owner_name)
          patch = safe_constant(patch_name)
          next unless owner && patch

          shadowed_methods(patch).each do |method_name|
            digest = digest_for(owner, patch, method_name)
            memo["#{owner_name}##{method_name}"] = digest if digest
          end
        end
      end

      # Public *and* private, because two of the copies are private in core --
      # Issue#workflow_rule_by_attribute among them, which is the method that
      # decides which fields are read-only or required. A first draft listed only
      # the public ones and silently covered thirteen of fifteen.
      def self.shadowed_methods(patch)
        (patch.instance_methods(false) + patch.private_instance_methods(false)).uniq.sort
      end

      # Core's body for one shadowed method, normalised and hashed. nil when the
      # plugin only adds the method, when core's definition is not in a file this
      # process can read, or when the AST is unavailable.
      def self.digest_for(owner, patch, method_name)
        source = core_source(owner, patch, method_name)
        source && Digest::SHA256.hexdigest(normalize(source))
      end

      # The text of core's definition, from the host's own checkout.
      #
      # **Two attachment styles, one question.** Where the patch is prepended,
      # core's version is one step up the chain and `super_method` is how to
      # reach it. Where it is attached to a controller's helper chain instead --
      # `WorkflowsHelperPatch` since finding F01 of 2026-08-28-claude-audit, for
      # the reason that patch's `apply!` gives at length -- the patch is *not* in
      # the owner's ancestors at all, so `instance_method` already answers with
      # core's own definition and `super_method` would answer nil. Asking which
      # of the two it is keeps the gate on both, and keeps it from silently
      # covering three fewer methods the day a patch changes how it attaches.
      def self.core_source(owner, patch, method_name)
        held = owner.instance_method(method_name)
        core = owner.ancestors.include?(patch) ? held.super_method : held
        return nil unless core
        return nil if core.owner == patch

        file, = core.source_location
        return nil unless file && File.readable?(file)

        node = RubyVM::AbstractSyntaxTree.of(core)
        return nil unless node

        File.readlines(file)[(node.first_lineno - 1)..(node.last_lineno - 1)].join
      rescue NameError, ScriptError, ArgumentError
        nil
      end

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
