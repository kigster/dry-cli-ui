# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Terminal do
  subject(:terminal) { described_class.new(io, env: env, **options) }

  let(:env) { {} }
  let(:options) { {} }

  context "on a pipe" do
    let(:io) { StringIO.new }

    it { is_expected.not_to be_tty }
    it { is_expected.not_to be_animated }
    it { is_expected.not_to be_color }
    its(:width) { is_expected.to eq(80) }
    its(:height) { is_expected.to eq(24) }
    its(:cursor) { is_expected.to eq(TTY::Cursor) }
    its(:io) { is_expected.to be(io) }
    it { expect(terminal.pastel.red("x")).to eq("x") }

    context "when forced to animate and colour" do
      let(:options) { { animate: true, color: true, width: 100 } }

      it { is_expected.to be_animated }
      it { is_expected.to be_color }
      its(:width) { is_expected.to eq(100) }
      it { expect(terminal.pastel.red("x")).to eq("\e[31mx\e[0m") }
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }

    before do
      allow(TTY::Screen).to receive_messages(width: 132, height: 50)
    end

    it { is_expected.to be_tty }
    it { is_expected.to be_animated }
    it { is_expected.to be_color }
    its(:width) { is_expected.to eq(132) }
    its(:height) { is_expected.to eq(50) }

    context "with NO_COLOR set" do
      let(:env) { { "NO_COLOR" => "1" } }

      it { is_expected.to be_animated }
      it { is_expected.not_to be_color }
    end

    context "with an empty NO_COLOR" do
      let(:env) { { "NO_COLOR" => "" } }

      it { is_expected.to be_color }
    end

    context "with TERM=dumb" do
      let(:env) { { "TERM" => "dumb" } }

      it { is_expected.not_to be_animated }
      it { is_expected.not_to be_color }
    end

    context "when forced off" do
      let(:options) { { animate: false, color: false } }

      it { is_expected.not_to be_animated }
      it { is_expected.not_to be_color }
    end
  end

  context "on an object that only knows how to print" do
    let(:io) { MinimalIO.new }

    it { is_expected.not_to be_tty }

    it "writes without flushing" do
      terminal.print("a")
      terminal.puts("b")
      expect(io.written).to eq(["a", "b\n"])
    end
  end

  describe "writing" do
    let(:io) { StringIO.new }

    before do
      allow(io).to receive(:flush).and_call_original
      terminal.print("a")
      terminal.puts("b")
      terminal.puts
    end

    it { expect(io.string).to eq("ab\n\n") }
    it { expect(io).to have_received(:flush).exactly(3).times }
  end
end
