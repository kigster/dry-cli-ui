# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Line do
  subject(:line) { described_class.new }

  its(:detail) { is_expected.to eq("") }
  its(:reason) { is_expected.to be_nil }
  it { is_expected.not_to be_failed }

  describe "#detail=" do
    it "stores the text as a String" do
      line.detail = 42
      expect(line.detail).to eq("42")
    end

    it "treats nil as no detail" do
      line.detail = nil
      expect(line.detail).to eq("")
    end

    it "tells whoever draws the line" do
      seen = []
      drawn = described_class.new { |text| seen << text }
      drawn.detail = "Resolving rules"
      expect(seen).to eq(["Resolving rules"])
    end
  end

  describe "#fail" do
    it "marks the line failed with a reason, and returns it" do
      expect(line.fail("offline")).to be(line)
      expect(line).to be_failed
      expect(line.reason).to eq("offline")
    end

    it "marks the line failed without a reason" do
      line.fail
      expect(line).to be_failed
      expect(line.reason).to be_nil
    end
  end

  describe "#summary" do
    it "is the label while the line has not failed" do
      expect(line.summary("Loading")).to eq("Loading")
    end

    it "adds the reason once the line has failed" do
      line.fail("offline")
      expect(line.summary("Loading")).to eq("Loading: offline")
    end

    it "is the label when the line failed without a reason" do
      line.fail("")
      expect(line.summary("Loading")).to eq("Loading")
    end
  end

  describe ".call" do
    it "gives the line to a block that takes it" do
      expect(described_class.call(->(given) { given }, line)).to be(line)
    end

    it "gives the line to a plain block that ignores it" do
      expect(described_class.call(proc { :done }, line)).to eq(:done)
    end

    it "calls a lambda that takes no arguments without it" do
      expect(described_class.call(-> { :done }, line)).to eq(:done)
    end
  end
end
