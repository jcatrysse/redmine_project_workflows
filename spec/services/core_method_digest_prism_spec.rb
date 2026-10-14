# frozen_string_literal: true

require_relative '../spec_helper'

# From Ruby 3.4 on every method is compiled by Prism, and
# `RubyVM::AbstractSyntaxTree.of` refuses such a method with a RuntimeError
# ("cannot get AST for ISEQ compiled by prism"). The drift gate read core's line
# ranges that way only, so on Ruby 3.4 and 4.0 every digest raised: on the
# diagnostics page and in init.rb's announcement on an unverified Redmine. The
# stub below is what Ruby 3.4 does, so the examples fail on the old code on any
# Ruby.
#
# The first two examples need Prism itself. Ruby 3.2 -- the Ruby of Redmine 5.1 --
# has no Prism in its default gems and compiles nothing with it, so the
# situation they stub cannot arise there and the fallback has nothing to load:
# they skip rather than assert a Ruby 3.4 behaviour on a Ruby that cannot have it.
describe RedmineProjectWorkflows::Services::CoreMethodDigest do
  def prism_loadable?
    require 'prism'
    true
  rescue LoadError
    false
  end

  def refuse_prism_compiled_methods
    allow(RubyVM::AbstractSyntaxTree).to receive(:of)
      .and_raise(RuntimeError, 'cannot get AST for ISEQ compiled by prism')
  end

  it 'reads the same bodies through Prism when the AST refuses a Prism-compiled method' do
    skip 'needs RubyVM::AbstractSyntaxTree' unless described_class.available?
    skip 'needs Prism, which this Ruby does not have' unless prism_loadable?

    measured = described_class.digests
    refuse_prism_compiled_methods

    expect(measured).not_to be_empty
    expect(described_class.digests).to eq(measured)
  end

  it 'still answers that it can measure when the AST refuses a Prism-compiled method' do
    skip 'needs RubyVM::AbstractSyntaxTree' unless described_class.available?
    skip 'needs Prism, which this Ruby does not have' unless prism_loadable?

    refuse_prism_compiled_methods

    expect(described_class).to be_available
  end

  it 'says it cannot measure when neither the AST nor Prism can read a definition' do
    refuse_prism_compiled_methods
    allow(described_class).to receive(:require).with('prism').and_raise(LoadError)

    expect(described_class).not_to be_available
  end
end
