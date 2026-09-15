# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::Spinner do
  subject(:spinner) { described_class.new(terminal, clock: FakeClock.new) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 80) }

  context "on a pipe" do
    let(:io) { StringIO.new }

    it "returns what the block returns" do
      expect(spinner.run("Loading") { 42 }).to eq(42)
    end

    it "prints the label, then the outcome" do
      spinner.run("Loading") { nil }
      expect(io.string).to eq("Loading...\n✓ Loading (0.5s)\n")
    end

    it "marks a failure and re-raises" do
      expect { spinner.run("Loading") { raise "boom" } }.to raise_error(RuntimeError, "boom")
      expect(io.string).to end_with("𝘅 Loading (0.5s)\n")
    end

    it "gives the block a line" do
      expect(spinner.run("Loading") { |line| line }).to be_a(Dry::CLI::UI::Line)
    end

    it "keeps the detail to itself" do
      spinner.run("Loading") { |line| line.detail = "rule 42" }
      expect(io.string).to eq("Loading...\n✓ Loading (0.5s)\n")
    end

    it "marks a failure the block reports, and still returns its value" do
      expect(spinner.run("Loading") { |line| line.fail("3 rules skipped") && :partial }).to eq(:partial)
      expect(io.string).to end_with("𝘅 Loading: 3 rules skipped (0.5s)\n")
    end

    it "names the reason when the block reports a failure and then raises" do
      expect { spinner.run("Loading") { |line| line.fail("offline") && raise("boom") } }.to raise_error("boom")
      expect(io.string).to end_with("𝘅 Loading: offline (0.5s)\n")
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }

    it "animates, clears the spinner, and leaves the outcome" do
      result = spinner.run("Loading") do
        sleep(0.05)
        :done
      end
      expect(result).to eq(:done)
      expect(io.string).to include("Loading", "\e[2K").and exclude("Loading...")
      expect(plain(io.string)).to end_with("✓ Loading (0.5s)\n")
    end

    it "stops the spinner when the block fails" do
      expect { spinner.run("Loading") { raise "boom" } }.to raise_error("boom")
      expect(plain(io.string)).to end_with("𝘅 Loading (0.5s)\n")
    end

    it "redraws the detail after the label" do
      spinner.run("Loading") do |line|
        line.detail = "rule 42"
        sleep(0.15)
      end
      expect(plain(io.string)).to include("Loading rule 42")
    end

    it "draws nothing after the label once the detail is cleared" do
      spinner.run("Loading") do |line|
        line.detail = "rule 42"
        line.detail = nil
        sleep(0.15)
      end
      expect(plain(io.string)).to include("⠙ Loading").and exclude("rule 42")
    end

    it "marks a failure the block reports" do
      spinner.run("Loading") { |line| line.fail("offline") }
      expect(plain(io.string)).to end_with("𝘅 Loading: offline (0.5s)\n")
    end
  end
end
