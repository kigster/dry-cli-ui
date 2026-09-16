# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::MultiSpinner do
  subject(:multi) { described_class.new(terminal, clock: clock) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 80) }
  let(:clock) { FakeClock.new }
  let(:fetch) do
    lambda do |m|
      m.spinner("fonts") { :fonts }
      m.spinner("images") { :images }
    end
  end

  context "on a pipe" do
    let(:io) { StringIO.new }

    it "returns what each job returned, in declaration order" do
      expect(multi.run("Fetching", &fetch)).to eq(%i[fonts images])
    end

    it "prints the title, each outcome, then the headline's" do
      multi.run("Fetching", concurrent: false, &fetch)
      expect(io.string).to eq(<<~TEXT)
        Fetching...
          [✓] fonts (0.5s)
          [✓] images (0.5s)
        ✓ Fetching (2.5s)
      TEXT
    end

    it "gives each job a line, and keeps its detail to itself" do
      lines = multi.run("Fetching") { |m| m.spinner("fonts") { |line| (line.detail = "woff2") && line } }
      expect(lines.first).to be_a(Dry::CLI::UI::Line)
      expect(io.string).not_to include("woff2")
    end

    it "marks a failure a job reports, and the headline, without raising" do
      multi.run("Fetching", concurrent: false) do |m|
        m.spinner("fonts") { |line| line.fail("offline") }
        m.spinner("images") { nil }
      end
      expect(io.string).to include("  [𝘅] fonts: offline (0.5s)\n", "  [✓] images").and end_with("𝘅 Fetching (2.5s)\n")
    end

    context "when a job raises" do
      let(:ran) { [] }

      before do
        expect do
          multi.run("Fetching", concurrent: false) do |m|
            m.spinner("fonts") { raise "boom" }
            m.spinner("images") { ran << :images }
          end
        end.to raise_error("boom")
      end

      it { expect(ran).to be_empty }
      it { expect(io.string).to include("  [𝘅] fonts (0.5s)\n", "  [—] images\n").and end_with("𝘅 Fetching (1.5s)\n") }
    end

    it "runs at most as many jobs at once as asked" do
      running = Concurrent::AtomicFixnum.new
      most = Concurrent::AtomicFixnum.new
      work = lambda do
        most.update { |seen| [seen, running.increment].max }
        sleep(0.02)
        running.decrement
      end
      multi.run("Fetching", concurrent: 2) { |m| 5.times { |n| m.spinner("job #{n}", &work) } }
      expect(most.value).to eq(2)
    end

    context "when a stop is asked for" do
      let(:stop) { Dry::CLI::UI::Stop.new }
      let(:ran) { Concurrent::Array.new }
      let(:jobs) do
        lambda do |m|
          m.spinner("fonts") { (ran << :fonts) && stop.stop! && :fonts }
          m.spinner("images") { (ran << :images) && :images }
        end
      end

      it "starts no more jobs one at a time, and marks the rest and the headline skipped" do
        expect(multi.run("Fetching", concurrent: false, stop: stop, &jobs)).to eq([:fonts, nil])
        expect(io.string).to include("  [✓] fonts", "  [—] images\n").and end_with("— Fetching (1.5s)\n")
      end

      it "starts no more jobs under a limit" do
        multi.run("Fetching", concurrent: 1, stop: stop, &jobs)
        expect(ran).to eq([:fonts])
      end

      it "has already started every job when they all run at once" do
        multi.run("Fetching", stop: stop, &jobs)
        expect(ran).to contain_exactly(:fonts, :images)
      end
    end

    it "rejects a job without a block" do
      expect { multi.run("Fetching") { |m| m.spinner("fonts") } }.to raise_error(ArgumentError, /needs a block/)
    end

    it "rejects an invalid concurrent" do
      expect { multi.run("Fetching", concurrent: 0, &fetch) }.to raise_error(ArgumentError, /positive Integer/)
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }
    let(:clock) { -> { 0.0 } }

    before { allow(TTY::Screen).to receive(:height).and_return(height) }

    context "with room for every row" do
      let(:height) { 24 }

      it "draws a row per job under the headline, and ends with every outcome" do
        multi.run("Fetching") do |m|
          m.spinner("fonts") { sleep(0.15) }
          m.spinner("images") { |line| (line.detail = "12 of 40") && sleep(0.15) }
        end
        expect(plain(io.string)).to include("├─ [ ] fonts", "└─ [ ] images", "images 12 of 40", "⠙")
        expect(plain(io.string)).to end_with("[✓] Fetching (0.0s)\n├─ [✓] fonts (0.0s)\n└─ [✓] images (0.0s)\n")
      end

      it "says it is stopping while the running jobs finish, and is done when none were skipped" do
        stop = Dry::CLI::UI::Stop.new
        multi.run("Fetching", stop: stop) { |m| m.spinner("fonts") { stop.stop! && sleep(0.15) } }
        expect(plain(io.string)).to include("] Fetching stopping\n").and end_with("[✓] Fetching (0.0s)\n└─ [✓] fonts (0.0s)\n")
      end

      it "takes its frames from the configuration" do
        config = Dry::CLI::UI::Configuration.new.tap { it.spinner_format = { interval: 50, frames: %w[A B] } }
        described_class.new(terminal, clock: clock, config: config).run("Fetching") { |m| m.spinner("fonts") { sleep(0.1) } }
        expect(plain(io.string)).to include("[A] Fetching", "[B] fonts")
      end
    end

    context "with more rows than the screen" do
      let(:height) { 4 }
      let(:drawn) { plain(io.string) }

      before do
        multi.run("Fetching", concurrent: 1) do |m|
          %w[a b c d].each { |name| m.spinner(name) { sleep(0.02) } }
        end
      end

      it "leaves out the jobs waiting" do
        expect(drawn).to start_with("[⠋] Fetching\n[⠋] Fetching\n└─ [⠋] a\n")
      end

      it "shows only the jobs running" do
        expect(drawn).to include("[⠋] Fetching\n└─ [⠋] c\n").and exclude("[✓] b")
      end

      it "ends with the headline alone" do
        expect(drawn).to end_with("[⠋] Fetching\n[✓] Fetching (0.0s)\n")
      end

      it "clears the rows below before each redraw" do
        expect(io.string).to include("\e[2A\e[J")
      end
    end
  end
end
