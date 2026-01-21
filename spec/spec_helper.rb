# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../../config/environment', __dir__)
require 'rspec/rails'

if defined?(RedmineProjectWorkflows) &&
   !WorkflowTransition.singleton_class.ancestors.include?(RedmineProjectWorkflows::Patches::WorkflowTransitionPatch)
  RedmineProjectWorkflows.apply_patches
end

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
end

