# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::Box do
  subject(:box) { described_class.new(terminal, width: width).render(paragraphs, title: title, color: color) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(StringIO.new, env: {}, width: 60, color: colored) }
  let(:colored) { false }
  let(:width) { nil }
  let(:paragraphs) { ["Could not validate rule US.2026.IRC.199A", "Missing dependency: taxable_income"] }
  let(:title) { "Error" }
  let(:color) { :red }
  let(:lines) { box.lines(chomp: true) }

  it "fills the terminal less the margin, one paragraph per argument" do
    expect(box).to eq(<<~BOX)
      ┌─ Error ────────────────────────────────────────────────┐
      │                                                        │
      │  Could not validate rule US.2026.IRC.199A              │
      │                                                        │
      │  Missing dependency: taxable_income                    │
      │                                                        │
      └────────────────────────────────────────────────────────┘
    BOX
  end

  context "with text longer than one line" do
    let(:paragraphs) { [(1..40).map { |n| "word#{n}" }.join(" ")] }

    it "keeps every word" do
      expect(box.scan(/word\d+/).size).to eq(40)
    end

    it "keeps every line inside the frame" do
      expect(lines.map(&:length).uniq).to eq([58])
    end
  end

  context "with a fixed width narrower than the terminal" do
    let(:width) { 30 }

    it { expect(lines.map(&:length).uniq).to eq([30]) }
  end

  context "with a fixed width wider than the terminal" do
    let(:width) { 500 }

    it { expect(lines.first.length).to eq(58) }
  end

  context "with a width below the minimum" do
    let(:width) { 3 }

    it { expect(lines.first.length).to eq(described_class::MIN_WIDTH) }
  end

  context "without a title" do
    let(:title) { nil }

    it { expect(lines.first).to match(/\A┌─+┐\z/) }
  end

  context "with colour" do
    let(:colored) { true }

    it { expect(box).to include("\e[31;1mError\e[0m") }
    it { expect(box).to include("\e[37m│\e[0m") }

    context "and a title without a colour" do
      let(:color) { nil }

      it { expect(box).to include("\e[1mError\e[0m") }
    end
  end
end
