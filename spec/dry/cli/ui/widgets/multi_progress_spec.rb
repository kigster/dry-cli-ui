# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::MultiProgress do
  subject(:multi) { described_class.new(terminal, clock: clock) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 80) }
  let(:clock) { FakeClock.new }
  let(:download) do
    lambda do |m|
      m.progress("a.zip", total: 3) { |bar| 3.times { bar.advance } && :a }
      m.progress("b.zip", total: 2) { |bar| bar.advance && :b }
    end
  end

  context "on a pipe" do
    let(:io) { StringIO.new }

    it "returns what each job returned, in declaration order" do
      expect(multi.run("Downloading", &download)).to eq(%i[a b])
    end

    it "prints the title, each job's count, then the total count" do
      multi.run("Downloading", concurrent: false, &download)
      expect(io.string).to eq(<<~TEXT)
        Downloading...
          [✓] a.zip 3/3 (0.5s)
          [✓] b.zip 1/2 (0.5s)
        ✓ Downloading 4/5 (2.5s)
      TEXT
    end

    it "marks a job that raised with the count it reached, and re-raises" do
      expect do
        multi.run("Downloading") { |m| m.progress("a.zip", total: 3) { |bar| bar.advance && raise("boom") } }
      end.to raise_error("boom")
      expect(io.string).to include("  [𝘅] a.zip 1/3").and end_with("𝘅 Downloading 1/3 (1.5s)\n")
    end

    it "rejects a total that is not a count" do
      expect { multi.run("Downloading") { |m| m.progress("a.zip", total: -1) { nil } } }
        .to raise_error(ArgumentError, /non-negative Integer/)
      expect(io.string).to be_empty
    end

    it "rejects a colour Pastel does not know" do
      expect { multi.run("Downloading") { |m| m.progress("a.zip", total: 1, color: :nope) { nil } } }
        .to raise_error(ArgumentError, /color must be a Pastel style/)
    end

    it "rejects a job without a block" do
      expect { multi.run("Downloading") { |m| m.progress("a.zip", total: 1) } }.to raise_error(ArgumentError, /needs a block/)
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }
    let(:clock) { FakeClock.new(0.25) }

    before { allow(TTY::Screen).to receive(:height).and_return(24) }

    it "draws a headline bar over a bar per job, aligned, then every outcome" do
      multi.run("Downloading") do |m|
        m.progress("a.zip", total: 4) do |bar|
          bar.advance(2)
          sleep(0.15)
          bar.advance(2)
        end
        m.progress("the-longest.zip", total: 4) do |bar|
          bar.advance
          sleep(0.15)
          bar.advance(3)
        end
      end
      drawn = plain(io.string)
      expect(drawn).to include("├─ [ ] a.zip", "  0%  0/8  ETA --", "├─ [⠙] a.zip           [◼", " ]  50%  2/4  ETA ", "└─ ")
      expect(drawn).to match(/Downloading +\[◼+ +\]  37%  3\/8  ETA \d/)
      expect(drawn).to match(/├─ \[✓\] a\.zip 4\/4 \(\d+\.\ds\)\n└─ \[✓\] the-longest\.zip 4\/4 \(\d+\.\ds\)\n\z/)
    end

    it "right-aligns every count to the widest one" do
      multi.run("Downloading") do |m|
        m.progress("small", total: 8) { |bar| bar.advance && sleep(0.15) }
        m.progress("large", total: 503) { |bar| bar.advance(8) && sleep(0.15) }
      end
      frame = plain(io.string).lines.each_cons(3).find { |rows| rows.first.include?("9/511") && rows.all?(/ETA/) }
      expect(frame.map { |line| line.index("  ETA") }.uniq.size).to eq(1)
      expect(frame.join).to include("      1/8  ETA", "    8/503  ETA", "    9/511  ETA")
    end

    it "lines every bar up in the same columns" do
      multi.run("Downloading") do |m|
        m.progress("a", total: 2) { |bar| bar.advance && sleep(0.15) }
        m.progress("a-much-longer-name", total: 2) { |bar| bar.advance && sleep(0.15) }
      end
      bars = plain(io.string).lines.grep(/ETA/).map { |line| [line.rindex("["), line.rindex("]")] }
      expect(bars.uniq.size).to eq(1)
    end

    it "draws a full bar for a job with nothing to do" do
      multi.run("Downloading") { |m| m.progress("empty", total: 0) { sleep(0.15) } }
      expect(plain(io.string)).to include("100%  0/0")
    end

    it "paints each bar in its own colour, and the rest in the configured one" do
      coloured = Dry::CLI::UI::Terminal.new(io, env: {}, width: 80, color: true)
      described_class.new(coloured, clock: clock).run("Scanning") do |m|
        m.progress("up", total: 2, color: :green) { |bar| bar.advance && sleep(0.15) }
        m.progress("down", total: 2, color: :red) { |bar| bar.advance && sleep(0.15) }
      end
      rows = io.string.lines
      expect(rows.grep(/up .*ETA/).last).to include("\e[32m◼")
      expect(rows.grep(/down .*ETA/).last).to include("\e[31m◼")
    end

    it "takes the bar's characters from the configuration" do
      config = Dry::CLI::UI::Configuration.new.tap { it.bar_format = :classic }
      described_class.new(terminal, clock: clock, config: config).run("Downloading") do |m|
        m.progress("a.zip", total: 2) { |bar| bar.advance && sleep(0.15) }
      end
      expect(plain(io.string)).to include("[=====").and exclude("◼")
    end
  end
end
