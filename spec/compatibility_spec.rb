# frozen_string_literal: true

require 'tmpdir'
require_relative 'spec_helper'

# ADR-002. The manifest, and the three states it resolves.
#
# The awkward part of testing this, and the reason for the +data_file+ seam:
# **every host the suite runs on is a verified one by construction**, so two of
# the three states are unreachable from a plain example. That is the same shape
# as the defect ADR-002 exists to fix -- the old drift spec skipped itself on an
# unmeasured host and could therefore never fail -- so the examples below put a
# synthetic manifest in front of the module instead of stubbing its methods:
# the YAML is loaded, the digests are really measured on this host, and only the
# *table* is fictional.
describe RedmineProjectWorkflows::Compatibility do
  after { described_class.reset! }

  # A manifest whose only measured minor is one this host is not, carrying the
  # digests given. Written to a real file, because reading the file is part of
  # what is under test.
  def manifest_file(minor:, digests:)
    path = File.join(Dir.tmpdir, "compatibility-#{SecureRandom.hex(4)}.yml")
    File.write(path, YAML.dump('sprite_icons_from' => '6.0',
                               'databases' => ['PostgreSQL'],
                               'dependencies' => described_class.dependencies,
                               'minors' => { minor => { 'ruby' => '3.3', 'rails' => '8.0',
                                                        'digests' => digests } }))
    path
  end

  describe 'the manifest itself' do
    it 'lists this host as a verified Redmine' do
      expect(described_class.verified_minors).to include(described_class.host_minor)
    end

    it 'orders the minors as versions, not as strings' do
      expect(described_class.verified_minors).to eq(described_class.verified_minors.sort_by do |minor|
        Gem::Version.new(minor)
      end)
      expect(described_class.newest_verified_minor).to eq(described_class.verified_minors.last)
    end

    # The one fact the lint gate depends on: RuboCop's TargetRailsVersion may
    # not be newer than the OLDEST supported host, or a version-gated cop pushes
    # code towards a Rails the 5.1 cell cannot run. spec/plugin_conventions_spec
    # asserts it against the running host; this asserts the manifest agrees, so
    # that adding a minor cannot quietly move the floor.
    it 'records a Ruby and a Rails for every minor' do
      described_class.verified_minors.each do |minor|
        expect(described_class.ruby_for(minor)).to match(/\A\d+\.\d+\z/), minor
        expect(described_class.rails_for(minor)).to match(/\A\d+\.\d+\z/), minor
      end
    end

    it 'records the Rails this host actually runs' do
      expect(described_class.rails_for(described_class.host_minor))
        .to eq(Rails::VERSION::STRING.split('.').first(2).join('.'))
    end

    it 'answers the sprite-icon question from the version, and gets this host right' do
      expect(described_class.core_sprite_icons?).to eq(Redmine::VERSION::MAJOR >= 6)
    end
  end

  # ADR-002, decision 1: the user-facing prose is one of the seven places a
  # version fact used to live independently. It stays hand-written -- it is
  # prose, and generating prose from YAML produces neither -- but it may not
  # disagree with the manifest, and this is what says so.
  #
  # **Two files, since the documentation was split in 0.1.6.** The README carries
  # the claim under *Requirements*, because a reader deciding whether to install
  # should not have to follow a link to find out whether their Redmine is
  # supported; `docs/compatibility.md` carries the same claim in full. Both are
  # checked, because a fact stated twice is a fact that can drift once.
  {
    'README.md' => /^## Requirements$.*?(?=^## |\z)/m,
    'docs/compatibility.md' => /^## Tested combinations$.*?(?=^## |\z)/m
  }.each do |file, section_pattern|
    describe file do
      let(:section) { File.read(File.expand_path("../#{file}", __dir__))[section_pattern] }
      # The lines that make the claim, so the assertion reads the claim rather
      # than every number on the page -- "0.1.0" and "Ruby 3.2" are both
      # `\d+\.\d+` and neither is a supported Redmine.
      let(:claim) { section[/Redmine.*/] }

      it 'has a section that claims a set of Redmine versions' do
        expect(section).not_to be_nil
        expect(claim).not_to be_nil
      end

      it 'claims exactly the minors the manifest lists' do
        expect(claim.scan(/\d+\.\d+/).uniq.sort).to eq(described_class.verified_minors.sort)
      end

      it 'names every database the manifest lists' do
        described_class.databases.each { |database| expect(section).to include(database) }
      end

      it 'names every Ruby the manifest records' do
        described_class.verified_minors.map { |minor| described_class.ruby_for(minor) }.uniq.each do |ruby|
          expect(section).to include("Ruby #{ruby}")
        end
      end
    end
  end

  describe 'the digests measured on this host' do
    before do
      skip("this Ruby cannot read core's AST") unless RedmineProjectWorkflows::Services::CoreMethodDigest.available?
    end

    # Unstubbed and meaningful on every one of the nine cells: the host's own
    # entry, compared against the host. Anything but an empty answer is either a
    # stale manifest or real drift, and both are worth a red example.
    it 'is exactly what the manifest holds for this host' do
      expect(described_class.drift_against(described_class.host_minor)).to be_empty
    end

    # And the mirror image, which is what makes the example above mean
    # something: comparing this host against a DIFFERENT minor does find
    # differences, so an empty answer is a measurement rather than a hash that
    # never gets built. 5.1 and 6.1 differ in four bodies; 6.1 and 7.0 in one.
    it 'is not empty against a minor this host is not' do
      other = (described_class.verified_minors - [described_class.host_minor]).first
      skip('the manifest lists only one minor') unless other

      expect(described_class.drift_against(other)).not_to be_empty
    end

    # F06 of 2026-08-28-claude-audit: the gate covered nineteen methods and none
    # of the three class methods, two of which are the ones INV-1's write
    # isolation is routed through. Named individually rather than counted,
    # because a count goes green again the moment anything else is added.
    #
    # It asks the MEASUREMENT, not the manifest. The first draft asked
    # `digests_for(host_minor).keys` -- the checked-in table -- and stayed green
    # with the singleton targets removed from CoreMethodDigest, because the
    # table still listed what the gate had stopped measuring. Probed by reverting
    # TARGETS on a host and watching this example not fail.
    it 'measures the class methods the write isolation is routed through' do
      expect(RedmineProjectWorkflows::Services::CoreMethodDigest.digests.keys)
        .to include('WorkflowTransition.replace_transitions',
                    'WorkflowPermission.replace_permissions',
                    'WorkflowRule.copy_one')
    end

    it 'measures the private core method the plugin calls without shadowing' do
      expect(RedmineProjectWorkflows::Services::CoreMethodDigest.digests.keys)
        .to include('Issue#roles_for_workflow')
      expect(RedmineProjectWorkflows::Services::CoreMethodDigest.missing_dependencies).to be_empty
    end
  end

  describe 'the three states' do
    it 'is verified on a host the manifest lists, and measures nothing to say so' do
      expect(RedmineProjectWorkflows::Services::CoreMethodDigest).not_to receive(:digests)

      expect(described_class.state).to eq(:verified)
      expect(described_class.drift).to be_empty
    end

    it 'is unverified, without drift, when the minor is unknown but the bodies agree' do
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: RedmineProjectWorkflows::Services::CoreMethodDigest.digests)

      expect(described_class.verified?).to be(false)
      expect(described_class.drift).to be_empty
      expect(described_class.state).to eq(:unverified)
    end

    it 'is drifted when a body the plugin copied is not the one it was measured against' do
      measured = RedmineProjectWorkflows::Services::CoreMethodDigest.digests
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: measured.merge('Issue#new_statuses_allowed_to' => 'x' * 64))

      expect(described_class.state).to eq(:drifted)
      expect(described_class.drift.map(&:method_name)).to eq(['Issue#new_statuses_allowed_to'])
      expect(described_class.drift.first.status).to eq(:changed)
      # Where to read the diff, which is the first thing the reader needs.
      expect(described_class.drift.first.source).to include('app/models/issue.rb')
    end

    # The fourth state, which ADR-002 does not list. Reading core's bodies needs
    # RubyVM::AbstractSyntaxTree, so a Ruby without it can answer the version
    # question and not the drift one -- and the wrong thing to do then is to
    # report the second state, which says "no drift was detected" about a
    # measurement that never ran. No supported host is such a Ruby, which is
    # precisely why the claim would go unchallenged if it were made.
    it 'says it could not measure, rather than that it found nothing' do
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: RedmineProjectWorkflows::Services::CoreMethodDigest.digests)
      allow(RedmineProjectWorkflows::Services::CoreMethodDigest).to receive(:available?).and_return(false)

      expect(described_class.state).to eq(:unmeasured)
      expect(described_class.announce!(Logger.new(output = StringIO.new))).to be_present
      expect(output.string).to include('cannot read')
      expect(output.string).not_to include('no drift')
    end

    # The status the digest cannot express: core no longer has the method at
    # all. That is the failure that raises NoMethodError rather than answering
    # differently, and it reads differently on the diagnostics page.
    it 'calls a method core no longer defines missing, not changed' do
      measured = RedmineProjectWorkflows::Services::CoreMethodDigest.digests
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: measured.merge('Issue#gone_from_core' => 'y' * 64))

      gone = described_class.drift.find { |entry| entry.method_name == 'Issue#gone_from_core' }

      expect(gone.status).to eq(:missing)
    end

    # And the other direction: core grows a method the plugin only adds, so the
    # plugin's version starts shadowing one nobody compared it against.
    it 'calls a method the manifest never measured added' do
      measured = RedmineProjectWorkflows::Services::CoreMethodDigest.digests
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: measured.except('Issue#tracker='))

      added = described_class.drift.find { |entry| entry.method_name == 'Issue#tracker=' }

      expect(added.status).to eq(:added)
    end
  end

  describe 'what it says in the log' do
    let(:output) { StringIO.new }
    # A real Logger over a StringIO rather than a double: it asserts the text
    # that reaches a log file, where a double would let a formatting change
    # through (docs/STATE.md's traps).
    let(:logger) { Logger.new(output) }

    it 'says nothing at all on a verified host' do
      expect(described_class.announce!(logger)).to be_nil
      expect(output.string).to be_empty
    end

    it 'names the version and the absence of drift on an unverified one' do
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: RedmineProjectWorkflows::Services::CoreMethodDigest.digests)
      described_class.announce!(logger)

      expect(output.string).to include('redmine_project_workflows')
      expect(output.string).to include(described_class.host_minor)
      expect(output.string).to include('no drift')
    end

    it 'names the drifted methods when there is drift' do
      measured = RedmineProjectWorkflows::Services::CoreMethodDigest.digests
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: measured.merge('Issue#new_statuses_allowed_to' => 'x' * 64))
      described_class.announce!(logger)

      expect(output.string).to include('Issue#new_statuses_allowed_to')
    end

    # Once per process. init.rb runs again on every code reload in development,
    # and a line per reload is a line nobody reads.
    it 'speaks once, however often init.rb is re-executed' do
      described_class.data_file = manifest_file(minor: '99.9',
                                                digests: RedmineProjectWorkflows::Services::CoreMethodDigest.digests)

      3.times { described_class.announce!(logger) }

      expect(output.string.lines.size).to eq(1)
    end
  end
end
