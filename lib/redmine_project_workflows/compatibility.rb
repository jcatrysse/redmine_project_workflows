# frozen_string_literal: true

module RedmineProjectWorkflows
  # Every version fact this plugin holds, in one object (ADR-002).
  #
  # Before this module the same question was answered in seven places --
  # `requires_redmine` in init.rb, the README's Compatibility section, the CI
  # matrix, `core_method_digests.yml`, `VersionHelper`, the drift spec and the
  # conventions spec -- and they could disagree without anything noticing. They
  # did: the plugin declared a floor of 5.1 and let every future Redmine boot,
  # while the drift spec *skipped* rather than failed on a minor it had no
  # digests for. An administrator could upgrade to a Redmine nobody had run this
  # plugin on, get a clean boot, and go on using an obsolete copy of the method
  # that decides which status transitions are permitted.
  #
  # **Facts, never probes.** A version question is answered from
  # `Redmine::VERSION` through this manifest, never by asking whether a method
  # exists. `respond_to?(:sprite_icon)` was this plugin's answer to "does the
  # host draw SVG icons?" until 2026-08-28, and on a real Redmine 5.1 the
  # `redmineup` gem and `redmine_ai_triage` both back-port that method -- so the
  # plugin drew Redmine 6 markup on a Redmine 5 host (finding F02 of
  # docs/review/findings/2026-08-28-claude-plugin-compat-5.1.md). A method name
  # is not owned by Redmine; a version number is.
  #
  # **Three states, not two.** `verified?` answers whether the running minor is
  # one the plugin has been measured against. When it is not, the plugin does not
  # refuse to work -- an out-of-range refusal bricks an installation on an upgrade
  # the administrator may have had no choice about, and disables precisely the
  # screens where they would put it right -- it *measures*: `state` is
  # +:unverified+ when every body the plugin copied is byte-identical to the
  # newest verified Redmine's, and +:drifted+ when one is not.
  #
  # What that proves, exactly, is written down in ADR-002 and repeated on the
  # diagnostics page: it proves nothing about how core *calls* those methods, and
  # it is offered as evidence rather than as safety.
  module Compatibility
    DATA_FILE = File.expand_path('compatibility.yml', __dir__)

    # One drifted method, as the diagnostics page and the log line report it.
    #
    # +status+ is +:changed+ (core's body differs from the verified one),
    # +:missing+ (the plugin expects a core method this host does not have, which
    # is the one that raises NoMethodError rather than answering differently) or
    # +:added+ (core now defines a method the plugin only added, so the plugin's
    # version silently shadows a core method nobody compared it against).
    Drift = Struct.new(:method_name, :status, :expected, :actual, :source, keyword_init: true)

    class << self
      def data
        @data ||= YAML.load_file(data_file).freeze
      end

      def data_file
        @data_file ||= DATA_FILE
      end

      # Settable, so that a spec can put a manifest in front of this module that
      # does not list the host it is running on. Two of the three states cannot
      # be reached otherwise -- every host the suite runs on is a verified one by
      # construction, which is exactly the property that let the old drift spec
      # skip itself into meaninglessness.
      def data_file=(path)
        reset!
        @data_file = path
      end

      # "5.1" => { "ruby" => ..., "rails" => ..., "digests" => {...} }
      def minors
        data.fetch('minors')
      end

      # Oldest first, which is the order the README and the diagnostics page
      # list them in. Compared as versions rather than as strings, because
      # "5.1" < "6.1" holds either way but "6.1" < "6.10" only one of them.
      def verified_minors
        minors.keys.sort_by { |minor| Gem::Version.new(minor) }
      end

      def newest_verified_minor
        verified_minors.last
      end

      # The running Redmine, as the manifest spells a minor.
      def host_minor
        "#{::Redmine::VERSION::MAJOR}.#{::Redmine::VERSION::MINOR}"
      end

      # The whole version, patch level and all, for the diagnostics page. The
      # manifest is measured per minor -- core does not change a method body in a
      # patch release -- so nothing compares against this; it is what an
      # administrator reads back to somebody.
      def host_version
        ::Redmine::VERSION.to_s
      end

      def verified?(minor = host_minor)
        minors.key?(minor)
      end

      def digests_for(minor)
        minors.dig(minor, 'digests') || {}
      end

      # "Issue#roles_for_workflow" => why the plugin depends on it. Core methods
      # the plugin calls without shadowing: they have no `super_method` to reach
      # and no visibility of their own to protect them, so nothing but this list
      # would notice one being renamed away.
      def dependencies
        data.fetch('dependencies')
      end

      def databases
        data.fetch('databases')
      end

      def ruby_for(minor)
        minors.dig(minor, 'ruby')
      end

      def rails_for(minor)
        minors.dig(minor, 'rails')
      end

      # From Redmine 6.0, where +IconsHelper#sprite_icon+ and
      # +app/assets/images/icons.svg+ arrived and the +icon icon-add+ CSS classes
      # stopped carrying a picture. Kept as a version in the manifest rather than
      # as a constant in a helper, because it is the same kind of fact as the
      # verified minors and belongs beside them.
      def core_sprite_icons?
        Gem::Version.new(host_minor) >= Gem::Version.new(data.fetch('sprite_icons_from'))
      end

      # :verified, :unverified, :drifted -- or :unmeasured, which ADR-002 does
      # not list and which exists so that the plugin never says "no drift was
      # detected" when it detected nothing. Reading core's bodies needs
      # RubyVM::AbstractSyntaxTree, so a Ruby without it can answer the version
      # question and not the drift one. No supported host is such a Ruby (every
      # Redmine in the manifest runs CRuby), which is exactly why the claim
      # would go unchallenged if it were made.
      #
      # Digests are computed lazily and only when the running minor is unknown,
      # so a verified host pays nothing at all -- the measurement is 34.5 ms for
      # nineteen methods on a 5.1 host, and a verified host already knows the
      # answer.
      def state
        return :verified if verified?
        return :unmeasured unless measurable?

        drift.empty? ? :unverified : :drifted
      end

      # Whether the drift half of the question can be answered on this Ruby at
      # all.
      def measurable?
        Services::CoreMethodDigest.available?
      end

      # Every body the plugin depends on that is not what the newest verified
      # Redmine holds. Empty on a verified host without measuring anything.
      def drift
        return @drift if defined?(@drift)

        @drift = verified? ? [] : measure_drift
      end

      # One line in the log, once per process, and only when there is something
      # to say. Called from init.rb, after the patches are applied -- every class
      # the digest reads is already loaded by then, so this adds no autoload of
      # its own.
      def announce!(logger = Rails.logger)
        return if @announced

        @announced = true
        message = log_message
        logger&.info("[redmine_project_workflows] #{message}") if message
        message
      end

      # Cleared between examples that move the manifest or the host under it.
      def reset!
        @data = nil
        @data_file = nil
        @announced = nil
        remove_instance_variable(:@drift) if defined?(@drift)
      end

      # What this host holds against what +minor+ was measured to hold. The seam
      # the diagnostics page and the specs both need: `drift` answers about the
      # comparison the plugin makes on its own behalf, and this answers about any
      # other, without stubbing anything.
      def drift_against(minor, actual = host_digests)
        expected = digests_for(minor)

        (expected.keys | actual.keys).sort.filter_map do |name|
          next if expected[name] == actual[name]

          drift_entry(name, expected[name], actual[name])
        end
      end

      def host_digests
        Services::CoreMethodDigest.available? ? Services::CoreMethodDigest.digests : {}
      end

      private

      def log_message
        case state
        when :verified
          nil
        when :unmeasured
          "Redmine #{host_minor} is not a version this plugin has been tested against " \
          "(#{verified_minors.join(', ')}), and this Ruby cannot read Redmine's own source, so no " \
          'comparison was possible.'
        when :unverified
          "Redmine #{host_minor} is not a version this plugin has been tested against " \
          "(#{verified_minors.join(', ')}), but no drift was detected in what it copied from core."
        else
          "Redmine #{host_minor} is not a version this plugin has been tested against " \
          "(#{verified_minors.join(', ')}), and #{drift.size} of the core methods it depends on " \
          "differ from Redmine #{newest_verified_minor}: #{drift.map(&:method_name).join(', ')}. " \
          'See Administration > Project workflow diagnostics.'
        end
      end

      # Compared against the NEWEST verified minor rather than against all of
      # them. An unknown minor is almost always a newer one, and "identical to
      # the newest Redmine we tested" is the sentence worth being able to say;
      # matching some older entry instead would be a weaker claim reported as
      # the same one.
      def measure_drift
        return [] unless Services::CoreMethodDigest.available?

        drift_against(newest_verified_minor)
      end

      # A nil digest on this host means core has no definition under the
      # plugin's -- the method was renamed or removed, which is the case that
      # raises rather than answering differently. A nil in the manifest means the
      # opposite: core has grown a method the plugin only added, so the plugin's
      # version now shadows one nobody has compared it against.
      def drift_entry(name, expected, actual)
        status = if actual.nil? then :missing
                 elsif expected.nil? then :added
                 else :changed
                 end
        Drift.new(method_name: name, status: status, expected: expected, actual: actual,
                  source: core_source_location(name))
      end

      # Where core defines it on this host, so that the first thing an
      # administrator is told is where to read the diff.
      def core_source_location(name)
        owner, separator, method_name = name.rpartition(/[#.]/)
        owner = owner.constantize
        owner = owner.singleton_class if separator == '.'
        held = owner.instance_method(method_name)
        core = held.super_method || held
        core.source_location&.join(':')
      rescue StandardError
        nil
      end
    end
  end
end
