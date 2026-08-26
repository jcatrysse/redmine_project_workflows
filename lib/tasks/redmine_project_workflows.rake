# frozen_string_literal: true

namespace :redmine_project_workflows do
  desc 'Delete exact duplicate rows from the workflows table (see external F06)'
  task deduplicate_workflow_rules: :environment do
    deleted = WorkflowRule.delete_duplicate_rules!
    puts "redmine_project_workflows: deleted #{deleted} duplicate workflow #{'row'.pluralize(deleted)}"
  end
end
