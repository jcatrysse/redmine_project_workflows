# frozen_string_literal: true

Redmine::Plugin.register :redmine_project_workflows do
  name 'Redmine Project Workflows'
  author 'Jan Catrysse'
  description 'Project workflows for Redmine'
  url 'https://github.com/jcatrysse/redmine_project_workflows'
  version '0.0.2'
  requires_redmine version_or_higher: '5.0'
end

require 'deface'
require_relative 'lib/redmine_project_workflows'

Rails.application.config.after_initialize do
  RedmineProjectWorkflows.apply_patches
  RedmineProjectWorkflows.load_deface_overrides!
end
