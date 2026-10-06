# frozen_string_literal: true

# One project's decision to run its own workflow for one (tracker, role) and one
# kind of rule.
#
# The row records the decision, not the rules. That is the whole point (ADR-001
# and INV-3): a project with a scope and no rules has an *empty* workflow --
# nothing is permitted -- while a project without a scope inherits the generic
# workflow. Deriving the answer from whether rule rows exist cannot tell those
# two apart.
#
# A scope replaces; it never merges (INV-5), and it is never inherited from a
# parent project (INV-6).
class ProjectWorkflowScope < ActiveRecord::Base
  TRANSITIONS = 'transitions'
  PERMISSIONS = 'permissions'
  RULE_TYPES = [TRANSITIONS, PERMISSIONS].freeze

  # The rule type each of Redmine's two workflow STI classes belongs to.
  RULE_TYPE_BY_MODEL_NAME = {
    'WorkflowTransition' => TRANSITIONS,
    'WorkflowPermission' => PERMISSIONS
  }.freeze

  belongs_to :project
  belongs_to :tracker
  belongs_to :role
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :project_id, :tracker_id, :role_id, presence: true
  validates :rule_type, inclusion: { in: RULE_TYPES }
  validates :project_id, uniqueness: { scope: %i[tracker_id role_id rule_type] }

  scope :transitions, -> { where(rule_type: TRANSITIONS) }
  scope :permissions, -> { where(rule_type: PERMISSIONS) }

  # Accepts either of Redmine's workflow classes or a rule type string, so that
  # callers holding a model class do not each repeat the mapping.
  def self.rule_type_for(model_or_rule_type)
    return model_or_rule_type if RULE_TYPES.include?(model_or_rule_type)

    name = model_or_rule_type.respond_to?(:name) ? model_or_rule_type.name : model_or_rule_type.to_s
    RULE_TYPE_BY_MODEL_NAME.fetch(name) do
      raise ArgumentError, "no workflow scope rule type for #{model_or_rule_type.inspect}"
    end
  end

  # The id to stamp into the audit columns. Nil for anonymous, and for a write
  # with no user behind it at all -- a rake task, a migration, a console.
  def self.author_id_for(user)
    user.is_a?(User) && user.logged? ? user.id : nil
  end

  # The workflow class a rule type stores its rules in -- the inverse of
  # .rule_type_for.
  def self.rule_model_for(rule_type)
    case rule_type
    when TRANSITIONS then WorkflowTransition
    when PERMISSIONS then WorkflowPermission
    else raise ArgumentError, "unknown workflow scope rule type #{rule_type.inspect}"
    end
  end
end
