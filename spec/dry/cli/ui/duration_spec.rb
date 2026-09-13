# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Duration do
  describe ".format" do
    {
      0 => "0.0s",
      0.42 => "0.4s",
      59.9 => "59.9s",
      60 => "1m 00s",
      62.7 => "1m 02s",
      3599 => "59m 59s",
      3600 => "1h 00m",
      3720 => "1h 02m"
    }.each do |seconds, expected|
      it { expect(described_class.format(seconds)).to eq(expected) }
    end
  end

  describe "CLOCK" do
    subject(:clock) { described_class::CLOCK }

    it { expect(clock.call).to be_a(Float) }
    it { expect(clock.call).to be <= clock.call }
  end
end
