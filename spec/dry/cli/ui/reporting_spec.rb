# frozen_string_literal: true

require "tmpdir"

RSpec.describe Dry::CLI::UI::Reporting do
  subject(:ui) { Dry::CLI::UI::Console.new(out: out, err: err, env: {}, width: 40, invocation: invocation) }

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:tmp) { Dir.mktmpdir }
  let(:invocation) do
    Dry::CLI::UI::Invocation.new(executable: "law-cli", action: "export", name: "Law::Export",
                                 started_at: Time.new(2026, 10, 8, 9, 5, 7), directory: tmp)
  end
  let(:report) { File.join(tmp, "log", "law-cli-export.2026-10-08.090507.log") }
  let(:worker) { Class.new { def fail_with(amount) = raise(ArgumentError, "bad #{amount}") }.new }
  let(:caught) { {} }

  before { FileUtils.mkdir_p(File.join(tmp, ".git")) }
  after { FileUtils.rm_rf(tmp) }

  describe "#output" do
    context "without -o" do
      subject(:result) { ui.output { |io| io.puts("plain") || :done } }

      before { result }

      it { is_expected.to eq(:done) }
      it { expect(out.string).to eq("plain\n") }
      it { expect(err.string).to be_empty }
    end

    context "with -o -" do
      before { ui.output("-") { ui.table([["a", 1]]) } }

      it { expect(plain(out.string)).to include("a", "1") }
    end

    context "with a bare -o" do
      subject(:result) do
        ui.output("") do |io|
          ui.table([["a", 1]], header: %w[Key Value])
          ui.success("done")
          ui.warn("careful")
          io.puts("plain")
          :done
        end
      end

      before { result }

      it { is_expected.to eq(:done) }
      it { expect(out.string).to be_empty }
      it { expect(File.read(report)).to include("\e[1mKey\e[0m", "Success", "plain") }
      it { expect(File.read(report).lines.last).to match(/\AClosed at \d{4}-\d\d-\d\d \d\d:\d\d:\d\d [-+]\d{4}\n\z/) }
      it { expect(plain(err.string)).to include("careful", "ℹ Report written to log/law-cli-export.2026-10-08.090507.log") }

      it "writes to out again afterwards" do
        ui.info("back")
        expect(out.string).to include("back")
      end
    end

    context "with a file" do
      before { ui.output("reports/x.txt") { ui.status("ok", level: :success) } }

      it { expect(File.read(File.join(tmp, "reports", "x.txt"))).to start_with("\e[32m✓\e[0m ok\n") }
    end

    context "when the block raises" do
      before do
        ui.output("") { raise ArgumentError, "bad" }
      rescue ArgumentError => caught[:error]
      end

      it { expect(caught[:error].message).to eq("bad") }
      it { expect(File.read(report)).to start_with("Closed at") }
      it { expect(plain(err.string)).to include("Report written to") }
    end

    it { expect { ui.output("") }.to raise_error(ArgumentError, "output needs a block") }
  end

  describe "#logging" do
    before { ui.logging("-", level: "info", format: "standard") { ui.logger.info("hello") } }

    it { expect(out.string).to include("Law::Export -- hello") }
    it { expect { ui.logging(nil) }.to raise_error(ArgumentError, "logging needs a block") }

    context "with a bare -l" do
      before { ui.logging("") { ui.logger.warn("to the file") } }

      it { expect(File.read(File.join(tmp, "log", "law-cli-export.log"))).to include("Law::Export -- to the file") }
    end
  end

  describe "#with_flags" do
    subject(:result) do
      ui.with_flags(dry_run: false, yes: true, output: "", log: "-", log_level: "debug", log_format: "json") do |io|
        ui.logger.debug("starting")
        io.puts("plain")
        :done
      end
    end

    before { result }

    it { is_expected.to eq(:done) }
    it { expect(out.string).to include('"message":"starting"').and exclude("plain") }
    it { expect(File.read(report)).to start_with("plain\n") }
    it { expect { ui.with_flags }.to raise_error(ArgumentError, "with_flags needs a block") }

    context "without any flag" do
      subject(:result) { ui.with_flags { |io| io.puts("plain") } }

      it { expect(out.string).to eq("plain\n") }
    end
  end

  describe "#logger" do
    subject { ui.logger }

    its(:name) { is_expected.to eq("Law::Export") }
    it { is_expected.to be(ui.logger) }

    context "in a console that was given no invocation" do
      subject { Dry::CLI::UI::Console.new(out: out, err: err).logger }

      its(:name) { is_expected.to eq(File.basename($PROGRAM_NAME)) }
    end
  end

  describe "#log_exception" do
    context "for an exception raised while logging at debug" do
      before do
        ui.logging("-", level: "debug") do
          worker.fail_with(42)
        rescue ArgumentError => caught[:error]
          ui.log_exception(caught[:error], "Import failed")
        end
      end

      it { expect(out.string).to include("E [", "Law::Export -- Import failed -- {locals: [{frame: ", 'locals: {amount: "42"}') }
      it { expect(out.string).to include("Exception: ArgumentError: bad 42") }
    end

    context "for an exception raised at info" do
      before do
        ui.logging("-") do
          worker.fail_with(42)
        rescue ArgumentError => caught[:error]
          ui.log_exception(caught[:error], level: :warn)
        end
      end

      it { expect(out.string).to include("W [", "Law::Export -- bad 42 -- Exception: ArgumentError: bad 42").and exclude("locals") }
    end

    it { expect(ui.log_exception(StandardError.new("x"))).to be_nil }
    it { expect { ui.log_exception(StandardError.new("x"), level: :loud) }.to raise_error(ArgumentError, /log level/) }
  end
end
