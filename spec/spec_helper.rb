# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../../config/environment', __dir__)
require 'rspec/rails'

# Deliberately no fallback that applies the patches when the host boot did not.
# Such a fallback hides the one failure mode that matters most here: an init.rb
# that registers its patches somewhere Rails never calls leaves the plugin doing
# nothing in a real installation, and a green suite would say otherwise.
# spec/plugin_conventions_spec.rb asserts the boot did apply them.

RSpec.configure do |config|
  fixtures_dir = File.expand_path('../../../test/fixtures', __dir__)

  # rspec-rails older versions (Redmine 5.1 setups)
  if config.respond_to?(:fixture_path=)
    config.fixture_path = fixtures_dir
    # rspec-rails newer versions (Redmine 6 setups)
  elsif config.respond_to?(:fixture_paths=)
    config.fixture_paths = [fixtures_dir]
  end

  # keep compatibility across rspec-rails versions
  if config.respond_to?(:use_transactional_fixtures=)
    config.use_transactional_fixtures = true
  end

  config.before(:suite) do
    WorkflowTransition.delete_all
    WorkflowPermission.delete_all
    WorkflowRule.delete_all if defined?(WorkflowRule)
  end

  # Rails resets CurrentAttributes around a request through the executor, which
  # does not wrap an example. Without this an example would see the previous
  # example's cached data.
  config.before do
    RedmineProjectWorkflows::Current.reset if defined?(RedmineProjectWorkflows::Current)
  end
end
