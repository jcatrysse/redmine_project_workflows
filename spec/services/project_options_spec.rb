# frozen_string_literal: true

require_relative '../spec_helper'

# The lists every project-scoped screen intersects its parameters with (INV-7).
# What is not on them cannot be named, so what they leave out matters as much as
# what they contain.
describe RedmineProjectWorkflows::Services::ProjectOptions do
  fixtures :projects, :roles, :trackers, :users, :members, :member_roles,
           :enabled_modules, :projects_trackers

  let(:project) { projects(:projects_001) }
  let(:manager) { roles(:roles_001) }
  let(:developer) { roles(:roles_002) }
  let(:reporter) { roles(:roles_003) }

  describe '.trackers' do
    it 'is the trackers the project has enabled, in Redmine\'s order' do
      expect(described_class.trackers(project)).to eq(project.trackers.sorted.to_a)
    end

    it 'leaves out a tracker the project has not enabled' do
      project.trackers = [trackers(:trackers_001)]

      expect(described_class.trackers(project)).to eq([trackers(:trackers_001)])
    end

    it 'is empty for a project with no tracker enabled' do
      project.trackers = []

      expect(described_class.trackers(project)).to eq([])
    end
  end

  describe '.roles' do
    it 'is the roles somebody holds in this project' do
      expect(described_class.roles(project)).to contain_exactly(manager, developer)
    end

    it 'leaves out a role nobody holds here' do
      expect(described_class.roles(project)).not_to include(reporter)
    end

    # The builtin roles have no members anywhere, so a project never sees them.
    # Deciding the workflow for the people who are *not* its members stays a
    # system administrator's job on the administration screens.
    it 'leaves out the builtin roles' do
      expect(described_class.roles(project).select(&:builtin?)).to eq([])
    end

    it 'leaves out a role that takes no part in a workflow' do
      developer.update!(permissions: [:view_issues])

      expect(described_class.roles(project)).to eq([manager])
    end

    it 'is empty for a project nobody is a member of' do
      Member.where(project_id: project.id).destroy_all

      expect(described_class.roles(project)).to eq([])
    end

    # Nothing is inherited between projects (INV-6), memberships included: a
    # role held in the parent is not a role held here.
    it 'does not borrow a role from the parent project' do
      child = projects(:projects_003)

      expect(described_class.roles(child)).to eq([])
      expect(described_class.roles(project)).to include(manager)
    end
  end
end
