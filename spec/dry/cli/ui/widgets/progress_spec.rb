# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::Progress do
  subject(:progress) { described_class.new(terminal, clock: FakeClock.new) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 80) }

  context "on a pipe" do
    let(:io) { StringIO.new }

    it "returns what the block returns" do
      expect(progress.run("Importing", total: 2) { :imported }).to eq(:imported)
    end

    it "prints the label, then the final count" do
      progress.run("Importing", total: 3) { |bar| 2.times { bar.advance } }
      expect(io.string).to eq("Importing...\n✓ Importing 2/3 (0.5s)\n")
    end

    it "marks a failure with the count reached, and re-raises" do
      expect do
        progress.run("Importing", total: 3) do |bar|
          bar.advance
          raise "boom"
        end
      end.to raise_error("boom")
      expect(io.string).to end_with("𝘅 Importing 1/3 (0.5s)\n")
    end

    it "rejects a total that is not a count" do
      expect { progress.run("Importing", total: -1) { nil } }.to raise_error(ArgumentError, /non-negative Integer/)
      expect { progress.run("Importing", total: 1.5) { nil } }.to raise_error(ArgumentError)
      expect(io.string).to be_empty
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }

    it "draws a bar with percent, count and ETA, then clears it" do
      progress.run("Importing", total: 4) { |bar| 4.times { bar.advance } }
      expect(io.string).to include("Importing [", "◼", "100%", "4/4", "ETA")
      expect(plain(io.string)).to end_with("✓ Importing 4/4 (0.5s)\n")
    end

    it "stops a bar that did not finish" do
      expect { progress.run("Importing", total: 4) { |bar| bar.advance && raise("boom") } }.to raise_error("boom")
      expect(plain(io.string)).to end_with("𝘅 Importing 1/4 (0.5s)\n")
    end

    it "draws no bar for an empty job" do
      progress.run("Importing", total: 0) { nil }
      expect(plain(io.string)).to eq("Importing...\n✓ Importing 0/0 (0.5s)\n")
    end
  end

  describe ".bar" do
    let(:config) { Dry::CLI::UI::Configuration.new }
    let(:pastel) { Pastel.new(enabled: true) }

    it "paints the finished part green, and all of it on gray" do
      expect(described_class.bar(pastel, config, 0.5, 4))
        .to eq("[\e[32;100m◼\e[0m\e[32;100m◼\e[0m\e[100m \e[0m\e[100m \e[0m]")
    end

    it "draws the characters alone when colour is off" do
      expect(described_class.bar(Pastel.new(enabled: false), config, 0.25, 4)).to eq("[◼   ]")
    end

    it "leaves out what is not set" do
      config.bar_color = nil
      config.bar_background = nil
      expect(described_class.bar(pastel, config, 1.0, 2)).to eq("[◼◼]")
    end
  end

  describe Dry::CLI::UI::Widgets::Progress::Handle do
    subject(:handle) { described_class.new(3, nil) }

    its(:total) { is_expected.to eq(3) }
    its(:current) { is_expected.to eq(0) }
    it { expect(handle.advance).to be(handle) }
    it { expect(handle.advance(2).current).to eq(2) }
    it { expect(handle.advance(10).current).to eq(3) }
    it { expect(handle.advance(-5).current).to eq(0) }
  end
end
