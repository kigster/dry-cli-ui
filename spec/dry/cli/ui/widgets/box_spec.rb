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

RSpec.describe Dry::CLI::UI::Widgets::Box, "#popup" do
  subject(:popup) { described_class.new(terminal, width: width).popup(paragraphs, title: title) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 60, color: false) }
  let(:width) { nil }
  let(:paragraphs) { ["h  help", "q  quit"] }
  let(:title) { "Keys" }

  context "on a pipe" do
    let(:io) { StringIO.new }

    it "is the same box as #render" do
      expect(popup).to eq(described_class.new(terminal).render(paragraphs, title: title))
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }
    # Each frame row is drawn after a cursor move to it, 1-based: ESC[row;colH.
    let(:rows) { popup.scan(/\e\[(\d+);(\d+)H([^\e]*)/).map { |row, col, text| [row.to_i, col.to_i, text] } }

    before { allow(TTY::Screen).to receive(:height).and_return(20) }

    it "saves the cursor first and restores it last, so nothing scrolls" do
      expect(popup).to start_with(TTY::Cursor.save).and end_with(TTY::Cursor.restore)
      expect(popup).not_to include("\n")
    end

    it "is only as wide as its content" do
      expect(rows.first.last).to eq("┌─ Keys ───────────┐")
    end

    it "is centred on the screen" do
      expect(rows.first.first(2)).to eq([7, 21])
      expect(rows.last.first(2)).to eq([13, 21])
    end

    it "keeps every paragraph" do
      expect(rows.map(&:last).join).to include("h  help", "q  quit")
    end

    context "without a title" do
      let(:title) { nil }

      it { expect(rows.first.last).to eq("┌──────────────────┐") }
    end

    context "with a long title" do
      let(:title) { "Everything the keyboard does" }

      it "is wide enough for the title" do
        expect(rows.first.last).to start_with("┌─ Everything the keyboard does ")
      end
    end

    context "with more text than fits" do
      let(:paragraphs) { [(1..40).map { |n| "word#{n}" }.join(" ")] }
      let(:width) { 30 }

      it "wraps to the box width" do
        expect(rows.map { |_, _, text| text.length }.max).to be <= 30
        expect(rows.map(&:last).join.scan(/word\d+/).size).to eq(40)
      end
    end

    context "on a screen shorter than the popup" do
      before { allow(TTY::Screen).to receive(:height).and_return(2) }

      it "starts at the top" do
        expect(rows.first.first).to eq(1)
      end
    end
  end
end
