# frozen_string_literal: true

require_relative 'spec_helper'
require 'yaml'

# The locale gate, which used to be checked by hand at the end of every session.
#
# Redmine falls back to English for a key a locale does not carry, silently, so
# a key added to en.yml and forgotten everywhere else looks translated on an
# English installation and is invisible everywhere it matters. The plugin's rule
# is that all eight files carry all the keys; this asserts it.
describe 'the locale files' do
  locales_dir = File.expand_path('../config/locales', __dir__)
  files = Dir.glob(File.join(locales_dir, '*.yml'))
  reference = File.join(locales_dir, 'en.yml')

  def keys_of(path)
    flatten_keys(YAML.unsafe_load_file(path).values.first)
  end

  # A pluralised value is a hash of plural forms, and those differ between
  # languages on purpose -- Polish has three where English has two -- so only
  # the key that carries them is compared, not the forms inside it.
  def flatten_keys(table)
    table.keys.map(&:to_s).sort
  end

  it 'has more than one locale to compare' do
    expect(files.size).to be > 1
  end

  it 'has an English file to compare against' do
    expect(files).to include(reference)
  end

  files.each do |path|
    context File.basename(path) do
      it 'parses' do
        expect { YAML.unsafe_load_file(path) }.not_to raise_error
      end

      it 'is a single top-level locale' do
        expect(YAML.unsafe_load_file(path).keys.size).to eq(1)
      end

      it 'carries every key English carries, and no key English does not' do
        expect(keys_of(path)).to eq(keys_of(reference))
      end

      # Key parity alone does not catch the failure that actually happens: a
      # pluralised key whose value is a hash missing the form Redmine will ask
      # for. Redmine's I18n applies only :one and :other, to every language it
      # ships -- Polish included, which is why pl.yml carries a note about
      # wording its plurals so that two forms are enough. A missing form is an
      # I18n::InvalidPluralizationData at render time, not a fallback.
      it 'carries both plural forms wherever English is pluralised' do
        table = YAML.unsafe_load_file(path).values.first
        english = YAML.unsafe_load_file(reference).values.first

        english.each do |key, value|
          next unless value.is_a?(Hash)

          expect(table[key]).to be_a(Hash), "#{key} is pluralised in English and is not here"
          expect(table[key].keys.map(&:to_s)).to include('one', 'other'),
                                                 "#{key} is missing a plural form: #{table[key].keys.inspect}"
        end
      end
    end
  end
end
