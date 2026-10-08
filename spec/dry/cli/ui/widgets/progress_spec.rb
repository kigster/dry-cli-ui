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

    it "ends with a failure, the count and the reason, when the block fails its handle" do
      result = progress.run("Copying", total: 3) { |bar| 3.times { bar.advance } && bar.fail("2 failed") && :copied }
      expect(result).to eq(:copied)
      expect(io.string).to eq("Copying...\n𝘅 Copying 3/3: 2 failed (0.5s)\n")
    end

    it "ends with a failure and the count alone when no reason is given" do
      progress.run("Copying", total: 1) { |bar| bar.advance.fail }
      expect(io.string).to end_with("𝘅 Copying 1/1 (0.5s)\n")
    end

    it "rejects a colour Pastel does not know, before the block runs" do
      expect { progress.run("Importing", total: 1, color: :nope) { raise "ran" } }
        .to raise_error(ArgumentError, "color must be a Pastel style or nil, got :nope")
      expect(io.string).to be_empty
    end

    it "rejects a total that is not a count" do
      expect { progress.run("Importing", total: -1) { nil } }.to raise_error(ArgumentError, /non-negative Integer/)
      expect { progress.run("Importing", total: 1.5) { nil } }.to raise_error(ArgumentError)
      expect(io.string).to be_empty
    end

    context "with units counted by outcome" do
      before do
        progress.run("Placing", total: 4) { |bar| bar.advance.advance(as: :failed).advance(2, as: :aux) }
      end

      it "ends with a check mark and the breakdown after the time" do
        expect(io.string).to eq("Placing...\n✓ Placing 4/4 (0.5s)  1 failed, 2 auxiliary\n")
      end
    end

    context "with every unit failed" do
      before { progress.run("Placing", total: 2) { |bar| bar.advance(2, as: :failed) } }

      it { expect(io.string).to end_with("✓ Placing 2/2 (0.5s)  2 failed\n") }
    end

    context "with nothing to process" do
      before { progress.run("Placing", total: 0) { nil } }

      it { expect(io.string).to eq("Placing...\n𝘅 Placing 0/0: nothing to process (0.5s)\n") }
    end

    context "with nothing to process and a reason of its own" do
      before { progress.run("Placing", total: 0) { |bar| bar.fail("no forms found") } }

      it { expect(io.string).to end_with("𝘅 Placing 0/0: no forms found (0.5s)\n") }
    end

    it "keeps the error, not nothing to process, when an empty job raises" do
      expect { progress.run("Placing", total: 0) { raise "boom" } }.to raise_error("boom")
      expect(io.string).to end_with("𝘅 Placing 0/0 (0.5s)\n")
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }

    it "draws a bar with a spinner, percent, count and ETA, then clears it" do
      progress.run("Importing", total: 4) { |bar| 4.times { bar.advance } }
      expect(io.string).to include("⠋ Importing [", "◼", "100%", "4/4", "ETA")
      expect(plain(io.string)).to match(/✓ Importing 4\/4 \(\d+\.\ds\)\n\z/)
    end

    it "stops a bar that did not finish" do
      expect { progress.run("Importing", total: 4) { |bar| bar.advance && raise("boom") } }.to raise_error("boom")
      expect(plain(io.string)).to match(/𝘅 Importing 1\/4 \(\d+\.\ds\)\n\z/)
    end

    it "turns its spinner while the work runs" do
      progress.run("Importing", total: 2) { |bar| bar.advance && sleep(0.15) }
      expect(io.string).to include("⠙ Importing [")
    end

    it "clears the bar before the outcome line" do
      progress.run("Importing", total: 1, &:advance)
      expect(io.string).to include("\e[2K\e[1G\e[?25h\e[32m✓\e[0m Importing")
    end

    it "paints the finished part in its own colour" do
      described_class.new(Dry::CLI::UI::Terminal.new(io, env: {}, width: 80, color: true), clock: FakeClock.new)
                     .run("Importing", total: 2, color: :red) { |bar| bar.advance(2) }
      expect(io.string).to include("\e[31m◼").and exclude("\e[32m◼")
    end

    it "draws no bar for an empty job, and ends it failed" do
      progress.run("Importing", total: 0) { nil }
      expect(plain(io.string)).to eq("Importing...\n𝘅 Importing 0/0: nothing to process (0.5s)\n")
    end

    context "with colour, and units counted by outcome" do
      let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 80, color: true) }

      before { progress.run("Placing", total: 4) { |bar| bar.advance(2, as: :failed).advance(as: :aux).advance } }

      it "draws the failed cells red, then the auxiliary ones yellow, then the rest green" do
        expect(io.string).to match(/\[(\e\[31m◼\e\[0m)+(\e\[33m◼\e\[0m)+(\e\[32m◼\e\[0m)+\] 100%/)
      end

      it "paints the breakdown's numbers" do
        expect(io.string).to include("\e[31m2 failed\e[0m, \e[33m1 auxiliary\e[0m\n")
      end
    end
  end

  describe ".bar" do
    let(:config) { Dry::CLI::UI::Configuration.new }
    let(:pastel) { Pastel.new(enabled: true) }

    it "paints the finished part green, on no background" do
      expect(described_class.bar(pastel, config, 0.5, 4)).to eq("[\e[32m◼\e[0m\e[32m◼\e[0m  ]")
    end

    it "paints all of it on the background, when one is set" do
      config.bar_background = :on_blue
      expect(described_class.bar(pastel, config, 0.5, 2)).to eq("[\e[32;44m◼\e[0m\e[44m \e[0m]")
    end

    it "draws the characters alone when colour is off" do
      expect(described_class.bar(Pastel.new(enabled: false), config, 0.25, 4)).to eq("[◼   ]")
    end

    it "paints the finished part in the colour given instead" do
      expect(described_class.bar(pastel, config, 0.5, 2, color: :red)).to eq("[\e[31m◼\e[0m ]")
    end

    it "leaves out what is not set" do
      config.bar_color = nil
      config.bar_background = nil
      expect(described_class.bar(pastel, config, 1.0, 2)).to eq("[◼◼]")
    end

    it "draws a bar of successes alone as it draws one without counts" do
      expect(described_class.bar(pastel, config, 0.5, 4, counts: { ok: 2, aux: 0, failed: 0 })).to eq(described_class.bar(pastel, config, 0.5, 4))
    end

    it "draws the failed cells, then the auxiliary ones, then the successes" do
      expect(described_class.bar(pastel, config, 1.0, 4, counts: { ok: 2, aux: 1, failed: 1 }))
        .to eq("[\e[31m◼\e[0m\e[33m◼\e[0m\e[32m◼\e[0m\e[32m◼\e[0m]")
    end

    it "draws a failed cell plain when its colour is not set" do
      config.bar_failed_color = nil
      expect(described_class.bar(pastel, config, 0.5, 2, counts: { ok: 0, aux: 0, failed: 1 })).to eq("[◼ ]")
    end
  end

  describe ".segments" do
    {
      [10, { ok: 8, aux: 0, failed: 2 }] => [2, 0, 8],
      [10, { ok: 1, aux: 1, failed: 1 }] => [4, 3, 3],
      [10, { ok: 999, aux: 0, failed: 1 }] => [1, 0, 9],
      [1, { ok: 1, aux: 0, failed: 1 }] => [1, 0, 0],
      [0, { ok: 1, aux: 1, failed: 1 }] => [0, 0, 0],
      [5, { ok: 0, aux: 0, failed: 0 }] => [0, 0, 5]
    }.each do |(filled, counts), cells|
      it "splits #{filled} cells for #{counts} as #{cells}" do
        expect(described_class.segments(filled, counts)).to eq(cells)
      end
    end
  end

  describe ".breakdown" do
    let(:config) { Dry::CLI::UI::Configuration.new }

    it { expect(described_class.breakdown(Pastel.new(enabled: false), config, { ok: 3, aux: 0, failed: 0 })).to be_nil }
    it { expect(described_class.breakdown(Pastel.new(enabled: false), config, { ok: 0, aux: 5, failed: 20 })).to eq("20 failed, 5 auxiliary") }
    it { expect(described_class.breakdown(Pastel.new(enabled: true), config, { ok: 0, aux: 5, failed: 0 })).to eq("\e[33m5 auxiliary\e[0m") }
  end

  describe ".eta" do
    it { expect(described_class.eta(0, 4) { raise "asked" }).to eq("--") }
    it { expect(described_class.eta(1, nil) { raise "asked" }).to eq("--") }
    it { expect(described_class.eta(1, 4) { 2.0 }).to eq("6.0s") }
  end

  describe ".outcome" do
    it { expect(described_class.outcome(:aux)).to eq(:aux) }
    it { expect { described_class.outcome(:skipped) }.to raise_error(ArgumentError, "as must be one of [:ok, :aux, :failed], got :skipped") }
  end

  describe Dry::CLI::UI::Widgets::Progress::Handle do
    subject(:handle) { described_class.new(3, nil) }

    its(:total) { is_expected.to eq(3) }
    its(:current) { is_expected.to eq(0) }
    its(:color) { is_expected.to be_nil }
    it { expect(handle.advance).to be(handle) }
    it { expect(handle.advance(2).current).to eq(2) }
    it { expect(handle.advance(10).current).to eq(3) }
    it { expect(handle.advance(-5).current).to eq(0) }

    context "with a total set later" do
      before { handle.advance(3).total = 2 }

      its(:total) { is_expected.to eq(2) }
      its(:current) { is_expected.to eq(2) }
    end

    context "without a total" do
      subject(:handle) { described_class.new(nil, nil) }

      its(:total) { is_expected.to be_nil }
      it { expect(handle.advance(500).current).to eq(500) }
    end

    context "with something to tell of changes" do
      subject(:handle) { described_class.new(nil, on_change) }

      let(:on_change) { instance_double(Proc, call: nil) }

      before { handle.advance.total = 9 }

      it { expect(on_change).to have_received(:call).twice }
    end

    its(:counts) { is_expected.to eq(ok: 0, aux: 0, failed: 0).and be_frozen }
    it { expect(handle.advance.advance(as: :failed).advance(as: :aux).counts).to eq(ok: 1, aux: 1, failed: 1) }
    it { expect(handle.advance(10, as: :failed).counts).to eq(ok: 0, aux: 0, failed: 3) }
    it { expect(handle.advance(2).advance(as: :failed).advance(-2, as: :failed).counts).to eq(ok: 1, aux: 0, failed: 0) }
    it { expect(handle.advance(as: :aux).advance(-1).counts).to eq(ok: 0, aux: 0, failed: 0) }
    it { expect { handle.advance(as: :skipped) }.to raise_error(ArgumentError, /as must be one of/) }

    context "with a total lowered below what was done" do
      before { handle.advance(2, as: :failed).advance.total = 1 }

      its(:counts) { is_expected.to eq(ok: 0, aux: 0, failed: 1) }
    end

    describe "#finish" do
      it { expect(handle.finish).to be(handle).and have_attributes(failed?: false) }
      it { expect(described_class.new(0, nil).finish).to have_attributes(failed?: true, reason: "nothing to process") }
      it { expect(described_class.new(0, nil).fail("none found").finish.reason).to eq("none found") }
      it { expect(described_class.new(nil, nil).finish).to have_attributes(failed?: false) }
    end

    it { expect { handle.total = nil }.to raise_error(ArgumentError, /non-negative Integer, got nil/) }
  end

  describe ".total" do
    it { expect(described_class.total(0)).to eq(0) }
    it { expect { described_class.total(-1) }.to raise_error(ArgumentError, /non-negative Integer/) }
  end
end
