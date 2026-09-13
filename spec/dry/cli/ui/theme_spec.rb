# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Theme do
  describe ".level" do
    subject(:level) { described_class.level(:error) }

    its(:title) { is_expected.to eq("Error") }
    its(:glyph) { is_expected.to eq("✗") }
    its(:color) { is_expected.to eq(:red) }
    its(:stream) { is_expected.to eq(:err) }
    it { is_expected.to be_frozen }

    it "rejects an unknown level" do
      expect { described_class.level(:loud) }.to raise_error(ArgumentError, /unknown level :loud/)
    end
  end

  describe "LEVELS" do
    subject(:streams) { described_class::LEVELS.transform_values(&:stream) }

    it "sends results to out and diagnostics to err" do
      expect(streams).to eq(debug: :err, info: :out, success: :out, warn: :err, error: :err, fatal: :err)
    end
  end
end
