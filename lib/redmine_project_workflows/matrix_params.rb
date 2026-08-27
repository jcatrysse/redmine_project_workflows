# frozen_string_literal: true

module RedmineProjectWorkflows
  # The shape of a submitted matrix, with core's "(No change)" option stripped
  # out at whatever depth the leaves are: transitions nest
  # status/status/rule and permissions status/field.
  #
  # Guarded at every level, unlike core's own two loops: `transitions[1]=x`
  # reaches those as a String and raises NoMethodError on `each_value`, which is
  # a 500 rather than a rejection.
  #
  # Included into ProjectWorkflowsController, which is why every method here is
  # **private**: every public instance method of a controller is an action, so a
  # public method here would be routable and unauthorized (CLAUDE.md's
  # forbidden-constructs table).
  #
  # The administration screens have their own copy of this idea in
  # Patches::WorkflowsControllerPatch#strip_no_change -- deliberately not shared:
  # that one works on core's parameters arriving through a core action, and the
  # two have diverged once already over whether a payload may be transposed
  # (finding F14). One place each, with the difference visible.
  module MatrixParams
    private

    def transitions_params
      transitions = to_plain_hash(params[:transitions])
      transitions.each_value do |transitions_by_new_status|
        next unless transitions_by_new_status.respond_to?(:each_value)

        transitions_by_new_status.each_value do |transition_by_rule|
          transition_by_rule.reject! { |_rule, transition| transition == 'no_change' } if transition_by_rule.is_a?(Hash)
        end
      end
      transitions
    end

    def permissions_params
      permissions = to_plain_hash(params[:permissions])
      permissions.each_value do |rule_by_field|
        rule_by_field.reject! { |_field, rule| rule == 'no_change' } if rule_by_field.is_a?(Hash)
      end
      permissions
    end

    def to_plain_hash(value)
      return {} if value.nil?
      return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      value.respond_to?(:to_h) ? value.to_h : {}
    end
  end
end
