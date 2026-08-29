# frozen_string_literal: true

namespace :redmine_project_workflows do
  desc 'Delete exact duplicate rows from the workflows table (see external F06)'
  task deduplicate_workflow_rules: :environment do
    deleted = WorkflowRule.delete_duplicate_rules!
    puts "redmine_project_workflows: deleted #{deleted} duplicate workflow #{'row'.pluralize(deleted)}"
  end

  desc 'Write every project workflow to FILE (JSON). FORCE=1 overwrites an existing file'
  task backup: :environment do
    path = RedmineProjectWorkflows::Tasks.required_file
    document = RedmineProjectWorkflows::Services::WorkflowBackup.write(path, force: ENV['FORCE'].present?)
    puts "redmine_project_workflows: wrote #{path}"
    puts RedmineProjectWorkflows::Tasks.summary(document).join("\n")
  end

  desc 'Restore project workflows from FILE. OVERWRITE=1 replaces workflows a project already has'
  task restore: :environment do
    path = RedmineProjectWorkflows::Tasks.required_file
    document = RedmineProjectWorkflows::Services::WorkflowBackup.read(path)
    report = RedmineProjectWorkflows::Services::WorkflowRestore.call(
      document, overwrite: ENV['OVERWRITE'].present?, user: User.anonymous
    )
    puts "redmine_project_workflows: restored from #{path}"
    puts report.lines.join("\n")
  end

  desc 'Back up, then reverse every migration. FILE= where to write it, CONFIRM=yes to go ahead'
  task uninstall: :environment do
    RedmineProjectWorkflows::Tasks.uninstall
  end
end
