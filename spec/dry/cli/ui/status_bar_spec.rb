# frozen_string_literal: true

require "tty-screen"

RSpec.describe Dry::CLI::UI::StatusBar do
  subject(:bar) { described_class.new(terminal, title: title, hints: hints, clock: -> { 0.0 }) }

  let(:io) { FakeTTY.new }
  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: width) }
  let(:width) { 60 }
  let(:title) { "deploy" }
  let(:hints) { ["^C cancel"] }
  let(:screen) { Screen.new(io.string) }

  before { allow(TTY::Screen).to receive(:height).and_return(24) }

  describe "#run" do
    it "returns what the block returns" do
      expect(bar.run { :deployed }).to eq(:deployed)
    end

    it "keeps a rule and the status line below whatever is written, then takes them away" do
      snapshot = nil
      bar.run do
        terminal.puts("first")
        terminal.puts("second")
        snapshot = Screen.new(io.string)
      end
      expect(snapshot.lines).to eq(["first", "second", "─" * 60, " · deploy · 0.0s#{' ' * 34}^C cancel"])
      expect(snapshot.cursor).to eq([2, 0])
      expect(screen.lines).to eq(%w[first second])
    end

    it "puts the cursor back after a write that does not end a line" do
      bar.run do
        terminal.print("Loading")
        terminal.print("...")
      end
      expect(screen.lines).to eq(["Loading..."])
    end

    it "keeps up with a spinner redrawing its own line" do
      snapshot = nil
      bar.run do
        terminal.print("\e[2K\e[1G⠋ Loading")
        terminal.print("\e[2K\e[1G⠙ Loading")
        snapshot = Screen.new(io.string)
      end
      expect(snapshot.lines.first(2)).to eq(["⠙ Loading", "─" * 60])
      expect(snapshot.cursor).to eq([0, 9])
    end

    it "sends a terminal's writes, and its widgets' reports, to the bar only while it runs" do
      inside = bar.run { [terminal.io, terminal.reporter, terminal.height] }
      expect(inside).to match([an_instance_of(described_class::Output), bar, 22])
      expect([terminal.io, terminal.reporter, terminal.height]).to eq([io, nil, 24])
    end

    it "takes the bar away when the block raises" do
      expect { bar.run { raise "boom" } }.to raise_error("boom")
      expect(screen.lines).to be_empty
      expect(terminal.io).to be(io)
    end

    it "redraws on its own, turning its spinner while work runs" do
      bar.run do
        bar.started(:job, "Compiling")
        sleep(0.25)
      end
      expect(plain(io.string)).to include("⠙ deploy · Compiling · 1 running")
    end

    it "draws on a stream that cannot flush, when told to animate" do
      minimal = MinimalIO.new
      forced = Dry::CLI::UI::Terminal.new(minimal, env: {}, animate: true, width: 60)
      described_class.new(forced, clock: -> { 0.0 }).run { forced.puts("hi") }
      expect(Screen.new(minimal.written.join).lines).to eq(["hi"])
    end

    it "also keeps another terminal's writes above it" do
      other = Dry::CLI::UI::Terminal.new(io, env: {}, width: 60)
      described_class.new(terminal, others: [other], clock: -> { 0.0 }).run { other.puts("result") }
      expect(screen.lines).to eq(["result"])
    end
  end

  describe "#line" do
    before { bar.instance_variable_set(:@started, 0.0) }

    context "on a wide terminal" do
      let(:width) { 120 }

      it "says what runs, what finished and how far the work has come" do
        handle = Dry::CLI::UI::Widgets::Progress::Handle.new(10, nil).advance(3)
        bar.started(:a, "Uploading", progress: handle)
        bar.started(:b, "Migrating users")
        bar.started(:c, "Warming")
        bar.finished(:c, true)
        bar.started(:d, "Cleaning")
        bar.finished(:d, false)
        expect(plain(bar.line)).to start_with(" ⠋ deploy · Migrating users · 2 running · 1 done · 1 failed · [◼◼◼       ] 30%")
      end

      it "counts progress without a total by what it did" do
        bar.started(:a, "Uploading", progress: Dry::CLI::UI::Widgets::Progress::Handle.new(nil, nil).advance(4))
        bar.started(:b, "Packing", progress: Dry::CLI::UI::Widgets::Progress::Handle.new(4, nil))
        expect(plain(bar.line)).to include("[◼◼◼◼◼     ] 50%")
      end

      it "keeps finished progress in the bar" do
        bar.started(:a, "Uploading", progress: Dry::CLI::UI::Widgets::Progress::Handle.new(4, nil).advance(4))
        bar.finished(:a, true)
        bar.started(:b, "Packing", progress: Dry::CLI::UI::Widgets::Progress::Handle.new(4, nil))
        expect(plain(bar.line)).to include("[◼◼◼◼◼     ] 50%")
      end
    end

    it "is as wide as the terminal, with the hints at the right edge" do
      expect(plain(bar.line).length).to eq(59)
      expect(plain(bar.line)).to end_with("^C cancel")
    end

    context "without a title or hints" do
      let(:title) { nil }
      let(:hints) { [] }

      it { expect(plain(bar.line)).to eq(" · 0.0s") }
    end

    context "when the hints do not fit" do
      let(:hints) { ["x" * 60] }

      it "leaves them out" do
        expect(plain(bar.line)).to eq(" · deploy · 0.0s")
      end
    end

    context "when the status itself does not fit" do
      let(:title) { "t" * 80 }

      it "truncates it" do
        expect(plain(bar.line).length).to be <= 59
        expect(plain(bar.line)).to end_with("…")
      end
    end
  end

  describe described_class::Column do
    subject(:column) { described_class.new }

    it "counts the columns text takes, and nothing for colour" do
      expect(column.follow("ab\e[31mc\e[0m")).to eq(3)
    end

    it "counts wide characters as two" do
      expect(column.follow("漢字")).to eq(4)
    end

    it "starts again after a line break or a carriage return" do
      expect([column.follow("abc\nde"), column.follow("\rx")]).to eq([2, 1])
    end

    it "follows moves to a column, right and left" do
      expect([column.follow("\e[5G"), column.follow("\e[G"), column.follow("\e[3C"), column.follow("\e[C"),
              column.follow("\e[2D"), column.follow("\e[9D")]).to eq([4, 0, 3, 4, 2, 0])
    end

    it "returns to a saved position" do
      expect([column.follow("ab\e7cd\e8"), column.follow("x\e[sy\e[u")]).to eq([2, 3])
    end

    it "ignores other control sequences and a stray escape" do
      expect(column.follow("a\e[?25l\e[2Kb\e")).to eq(2)
    end
  end

  describe described_class::Output do
    subject(:output) { described_class.new(io, bar) }

    let(:bar) { instance_double(Dry::CLI::UI::StatusBar, around_write: nil) }
    let(:io) { StringIO.new }

    it "writes through the bar and says how much it wrote" do
      expect(output.write("ab", "c")).to eq(3)
      expect(bar).to have_received(:around_write).with(io, "abc")
    end

    it { expect(output.print("x")).to be_nil }
    it { expect(output << "x").to be(output) }
    it { expect(output.tty?).to be(true) }
    it { expect { output.flush }.not_to raise_error }
    it { expect { described_class.new(MinimalIO.new, bar).flush }.not_to raise_error }

    it "answers what the stream answers" do
      expect(output).to respond_to(:string)
      expect(output.string).to eq("")
    end

    it "answers nothing else" do
      expect(output).not_to respond_to(:sparkle)
      expect { output.sparkle }.to raise_error(NoMethodError)
    end
  end
end
