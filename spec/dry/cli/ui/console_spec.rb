# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Console do
  subject(:ui) { described_class.new(out: out, err: err, input: input, env: {}, width: 40, box_width: box_width, clock: FakeClock.new) }

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:input) { StringIO.new("production\ny\n") }
  let(:box_width) { nil }

  describe "message boxes" do
    {
      debug: [:err, "Debug"], info: [:out, "Info"], success: [:out, "Success"],
      warn: [:err, "Warning"], error: [:err, "Error"], fatal: [:err, "Fatal"]
    }.each do |level, (stream, title)|
      describe "##{level}" do
        let(:written) { stream == :out ? out.string : err.string }
        let(:other) { stream == :out ? err.string : out.string }

        before { ui.public_send(level, "first", "second") }

        it { expect(written).to start_with("┌─ #{title} ") }
        it { expect(written).to include("│  first ", "│  second ") }
        it { expect(other).to be_empty }
      end
    end

    it "returns nil" do
      expect(ui.info("x")).to be_nil
    end

    it "accepts a width for one box" do
      ui.info("x", width: 25)
      expect(out.string.lines.first.chomp.length).to eq(25)
    end

    context "with a console box width" do
      let(:box_width) { 30 }

      before { ui.info("x") }

      it { expect(out.string.lines.first.chomp.length).to eq(30) }
    end
  end

  describe "#box" do
    it "is untitled by default and goes to out" do
      ui.box("plain panel")
      expect(out.string.lines.first).to match(/\A┌─+┐$/)
    end

    it "takes a title" do
      ui.box("Name: Alan Turing", title: "Profile")
      expect(out.string).to start_with("┌─ Profile ")
    end

    it "takes a level's title and stream" do
      ui.box("careful", level: :warn)
      expect(err.string).to start_with("┌─ Warning ")
    end

    it "lets a title override the level's" do
      ui.box("careful", level: :warn, title: "Heads up")
      expect(err.string).to start_with("┌─ Heads up ")
    end
  end

  describe "#popup" do
    it "draws a box on err" do
      expect(ui.popup("h  help", title: "Keys")).to be_nil
      expect(err.string).to start_with("┌─ Keys ")
      expect(out.string).to be_empty
    end

    it "accepts a width" do
      ui.popup("x", width: 25)
      expect(err.string.lines.first.chomp.length).to eq(25)
    end
  end

  describe "#status" do
    it "prints one line" do
      expect(ui.status("Connected", "to", "db")).to be_nil
      expect(out.string).to eq("ℹ Connected to db\n")
    end

    it "uses the level's glyph and stream" do
      ui.status("Disk nearly full", level: :warn)
      expect(err.string).to eq("⚠ Disk nearly full\n")
    end
  end

  describe "#spinner" do
    it "runs the block on err and returns its value" do
      expect(ui.spinner("Loading") { :rules }).to eq(:rules)
      expect(err.string).to eq("Loading...\n✓ Loading (0.5s)\n")
    end

    it { expect { ui.spinner("Loading") }.to raise_error(ArgumentError, /needs a block/) }
  end

  describe "#progress" do
    it "runs the block on err and returns its value" do
      expect(ui.progress("Importing", total: 1) { |bar| bar.advance && :ok }).to eq(:ok)
      expect(err.string).to end_with("✓ Importing 1/1 (0.5s)\n")
    end

    it { expect { ui.progress("Importing", total: 1) }.to raise_error(ArgumentError, /needs a block/) }
  end

  describe "#multi_spinner" do
    it "runs every job on err and returns their values" do
      expect(ui.multi_spinner("Fetching") { |m| m.spinner("fonts") { :fonts } }).to eq([:fonts])
      expect(err.string).to start_with("Fetching...\n").and include("  [✓] fonts")
      expect(out.string).to be_empty
    end

    it { expect { ui.multi_spinner("Fetching") }.to raise_error(ArgumentError, /needs a block/) }
  end

  describe "#multi_progress" do
    it "runs every job on err and returns their values" do
      expect(ui.multi_progress("Downloading") { |m| m.progress("a", total: 1) { |bar| bar.advance && :a } }).to eq([:a])
      expect(err.string).to include("  [✓] a 1/1").and end_with("1/1 (1.5s)\n")
      expect(out.string).to be_empty
    end

    it { expect { ui.multi_progress("Downloading") }.to raise_error(ArgumentError, /needs a block/) }
  end

  describe "#status_bar" do
    it { expect { ui.status_bar("deploy") }.to raise_error(ArgumentError, /needs a block/) }

    it "only runs the block when err is not a terminal" do
      expect(ui.status_bar("deploy") { :done }).to eq(:done)
      expect(err.string).to be_empty
    end

    context "on a terminal" do
      subject(:ui) { described_class.new(out: out, err: err, env: {}, width: 80, clock: -> { 0.0 }) }

      let(:err) { FakeTTY.new }
      let(:out) { FakeTTY.new }
      let(:frames) { [] }

      before { allow(TTY::Screen).to receive(:height).and_return(24) }

      it "hears from every widget run inside it, and leaves only their output behind" do
        status = -> { plain(Screen.new(err.string).lines.last) }
        result = ui.status_bar("deploy", hints: "^C cancel") do
          ui.spinner("Loading") do
            sleep(0.12)
            frames << status.call
          end
          ui.progress("Importing", total: 2) { |bar| bar.advance(2) }
          ui.multi_progress("Uploading") { |m| m.progress("a", total: 4) { |bar| bar.advance(2) } }
          ui.tasks("Migrate") { |t| t.task("users") { |line| line.fail("locked") } }
          frames << status.call
          :deployed
        end
        expect(result).to eq(:deployed)
        expect(frames.first).to include("deploy · Loading · 1 running").and end_with("^C cancel")
        expect(frames.last).to include("3 done · 1 failed · [◼◼◼◼◼◼    ] 66%")
        expect(plain(Screen.new(err.string).lines.last)).to eq("└─ [𝘅] users: locked (0.0s)")
      end

      it "leaves results alone when out is not a terminal" do
        piped = StringIO.new
        described_class.new(out: piped, err: err, env: {}, width: 80).status_bar { ui.info("hello") }
        expect(piped.string).not_to include("\e[J")
      end

      it "keeps the console's results above it too" do
        ui.status_bar { ui.info("hello") }
        expect(out.string).to include("hello", "\e[J")
      end

      it "only runs the block inside another status bar" do
        inner = nil
        ui.status_bar("outer") { ui.status_bar("inner") { inner = err.string.dup } }
        expect(inner).not_to include("inner")
      end
    end
  end

  describe "#tasks" do
    it "runs the tree on err" do
      ui.tasks("Deploy") { |t| t.task("Build") { nil } }
      expect(err.string).to eq("Deploy\n└─ [✓] Build (0.5s)\n")
    end

    it { expect { ui.tasks("Deploy") }.to raise_error(ArgumentError, /needs a block/) }
  end

  describe "#table" do
    it "prints to out" do
      expect(ui.table([["Alan Turing", 41]], header: %w[Name Age])).to be_nil
      expect(out.string).to include("│ Alan Turing │ 41  │")
    end
  end

  describe "#prompt and #confirm" do
    it "asks on err and reads from input" do
      expect(ui.prompt("Environment?", choices: %w[staging production])).to eq("production")
      expect(ui.confirm("Deploy?")).to be(true)
      expect(err.string).to include("Environment?", "Deploy? (y/N)")
    end

    it "passes a default through" do
      expect(ui.prompt("Name?", default: "Ada")).to eq("production")
      expect(ui.confirm("Again?", default: true)).to be(true)
    end
  end

  context "when neither stream is a terminal" do
    before do
      ui.info("info")
      ui.error("error")
      ui.status("status", level: :success)
      ui.spinner("spinner") { nil }
      ui.progress("progress", total: 2) { |bar| bar.advance(2) }
      ui.tasks("tasks") { |t| t.group("group") { |g| g.task("task") { nil } } }
      ui.table([["a", 1]], header: %w[name count])
      ui.prompt("prompt?")
      ui.confirm("confirm?")
    end

    it "writes no escape sequences at all" do
      expect(out.string + err.string).not_to include("\e")
    end
  end

  context "with default streams" do
    subject(:ui) { described_class.new }

    it "writes results to $stdout" do
      expect { ui.status("hello") }.to output("ℹ hello\n").to_stdout
    end
  end
end
