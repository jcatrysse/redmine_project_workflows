# frozen_string_literal: true

require_relative '../spec_helper'

# The drift gate (ADR-002) digests *core's* body of every method the plugin
# shadows. It walked down past the plugin's own definitions and took the first
# other one -- which, on a host where another plugin also prepends the method,
# is that plugin's wrapper, not core. On the combined GEOxyz host that made
# compatibility_spec and core_drift_spec report redmine_itil_priority's
# WorkflowsController#permissions as "core changed", and would have made an
# unverified host warn about drift that is not there. Core's body is the one
# the class itself defines; anything prepended in front of it is skipped.
class DigestSpecPlainHost
  def greet
    :core
  end
end

class DigestSpecCrowdedHost
  def greet
    :core
  end
end

module DigestSpecNeighbourBefore
  def greet
    super || :neighbour
  end
end

module DigestSpecNeighbourAfter
  def greet
    super || :neighbour
  end
end

module RedmineProjectWorkflows
  module DigestSpecPatch
    def greet
      :plugin
    end
  end
end

# A neighbour loaded before the plugin, the plugin, then one loaded after it.
DigestSpecCrowdedHost.prepend(DigestSpecNeighbourBefore)
DigestSpecCrowdedHost.prepend(RedmineProjectWorkflows::DigestSpecPatch)
DigestSpecCrowdedHost.prepend(DigestSpecNeighbourAfter)
DigestSpecPlainHost.prepend(RedmineProjectWorkflows::DigestSpecPatch)

describe RedmineProjectWorkflows::Services::CoreMethodDigest do
  it "digests the class's own body, not a neighbour plugin's wrapper prepended in front of it" do
    skip 'needs RubyVM::AbstractSyntaxTree' unless described_class.available?

    patch = RedmineProjectWorkflows::DigestSpecPatch
    plain = described_class.digest_for(DigestSpecPlainHost, patch, :greet)

    expect(plain).to be_present
    expect(described_class.digest_for(DigestSpecCrowdedHost, patch, :greet)).to eq(plain)
  end
end
