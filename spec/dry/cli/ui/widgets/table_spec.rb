# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::Table do
  subject(:table) { described_class.new(terminal).render(rows, header: header) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(StringIO.new, env: {}, color: colored) }
  let(:colored) { false }
  let(:rows) { [["Alan Turing", 41], ["Ada Lovelace", 36]] }
  let(:header) { %w[Name Age] }

  it do
    expect(table).to eq(<<~TABLE)
      ┌──────────────┬─────┐
      │ Name         │ Age │
      ├──────────────┼─────┤
      │ Alan Turing  │ 41  │
      │ Ada Lovelace │ 36  │
      └──────────────┴─────┘
    TABLE
  end

  context "without a header" do
    let(:header) { nil }

    it { expect(table.lines.size).to eq(4) }
  end

  context "without rows" do
    let(:rows) { [] }

    it { is_expected.to eq("") }
  end

  context "with colour" do
    let(:colored) { true }

    it { is_expected.to include("\e[1mName\e[0m") }
  end

  context "wider than the terminal" do
    let(:rows) { [["x", "long " * 40]] }

    it "neither truncates nor rotates it" do
      expect(table.lines[1]).to match(/Name\s+│ Age/)
      expect(table).to include(("long " * 40).strip)
    end

    it "prints no warning" do
      expect { table }.not_to output.to_stderr
    end
  end
end
