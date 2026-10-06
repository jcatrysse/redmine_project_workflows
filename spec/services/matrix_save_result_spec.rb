# frozen_string_literal: true

require_relative '../spec_helper'

# F01 (2026-08-27-bundled-followup). The administration matrices write one
# population per selected project and add the results up, so what `#+` does with
# each member decides what the screen may claim. Two of the three members are
# counts *of combinations* -- one population's combinations are not another's, so
# they add. `rejected` is a count *of submitted values*, and the submission is
# the same one for every population, so adding it multiplies one bad value by the
# size of the selection: one unacceptable value on an "all projects" save of a
# five-hundred-project installation reported itself as five hundred.
#
# Asserted here, at the struct, rather than only through the two controller
# examples that used to encode the multiplied number: this is the method a reader
# goes to for the answer, and it is the only place the asymmetry can be stated.
describe RedmineProjectWorkflows::Services::MatrixSaveResult do
  describe '#+' do
    it 'adds the counts of combinations' do
      combined = described_class.new(2, 1, 0) + described_class.new(3, 4, 0)

      expect(combined).to have_attributes(written: 5, skipped: 5)
    end

    # The property the flash sentence needs: "%{count} submitted values were not
    # accepted" has to be the number of values in the request, whatever the
    # selection was resolved into.
    it 'counts one submission of rejected values once, not once per population' do
      one_population = described_class.new(1, 0, 2)

      combined = one_population + one_population

      expect(combined.rejected).to eq(2)
    end

    it 'reports rejected values once across a whole selection' do
      per_population = described_class.new(1, 0, 1)

      combined = ([per_population] * 500).sum(described_class.none)

      expect(combined).to have_attributes(written: 500, skipped: 0, rejected: 1)
    end

    # Defensive rather than reachable: both whitelists are built from
    # installation-wide lists (IssueStatus ids, core field names, the two rule
    # tables), so every population refuses exactly the same leaves today. If one
    # ever refused more, the larger number is the honest one -- that many values
    # really were not accepted -- and it is the reason this is a maximum rather
    # than "take the first result's".
    it 'keeps the largest count when two populations disagree' do
      combined = described_class.new(1, 0, 1) + described_class.new(1, 0, 3)

      expect(combined.rejected).to eq(3)
      expect((described_class.new(1, 0, 3) + described_class.new(1, 0, 1)).rejected).to eq(3)
    end

    it 'leaves a result unchanged when added to none' do
      result = described_class.new(2, 3, 4)

      expect(described_class.none + result).to have_attributes(written: 2, skipped: 3, rejected: 4)
      expect(result + described_class.none).to have_attributes(written: 2, skipped: 3, rejected: 4)
    end
  end
end
