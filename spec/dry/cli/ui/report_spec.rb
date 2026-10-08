# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Report do
  subject(:report) { described_class.new(io) }

  let(:io) { StringIO.new }

  it { is_expected.to be_color }
  it { is_expected.not_to be_tty }
  it { expect(report.__getobj__).to be(io) }

  it "writes to the IO it wraps" do
    report.puts("hello")
    expect(io.string).to eq("hello\n")
  end

  it "makes a terminal on it colour although it is no TTY" do
    expect(Dry::CLI::UI::Terminal.new(report, env: {})).to be_color
  end

  it "makes no colour under NO_COLOR" do
    expect(Dry::CLI::UI::Terminal.new(report, env: { "NO_COLOR" => "1" })).not_to be_color
  end
end
