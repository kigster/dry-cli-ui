# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe Dry::CLI::UI::Logging do
  subject(:logging) { described_class.new(target, io: io, level: level, format: format) }

  let(:target) { "-" }
  let(:io) { StringIO.new }
  let(:level) { "info" }
  let(:format) { "standard" }
  let(:logger) { described_class.logger("Importer") }
  let(:caught) { {} }
  let(:worker) do
    Class.new do
      def fail_with(amount) = raise(ArgumentError, "bad #{amount}")

      def again(amount)
        fail_with(amount)
      rescue ArgumentError
        raise
      end

      def deep(depth) = depth.zero? ? raise("bottom") : deep(depth - 1)
    end.new
  end

  describe ".level" do
    it { expect(described_class.level("debug")).to eq(:debug) }
    it { expect(described_class.level(:warn)).to eq(:warn) }

    it "refuses a level -L does not take" do
      expect { described_class.level("trace") }
        .to raise_error(ArgumentError, 'unknown log level "trace", expected one of debug, info, warn, error, fatal')
    end
  end

  describe ".formatter" do
    it { expect(described_class.formatter("standard")).to be_a(SemanticLogger::Formatters::Default) }
    it { expect(described_class.formatter("json")).to be_a(SemanticLogger::Formatters::Json) }
    it { expect(described_class.formatter(:logfmt)).to be_a(SemanticLogger::Formatters::Logfmt) }

    it "refuses a format SemanticLogger does not have, naming those it does" do
      expect { described_class.formatter("yaml") }
        .to raise_error(ArgumentError, /unknown log format "yaml", expected one of .*json.*standard/)
    end
  end

  describe ".formats" do
    subject { described_class.formats }

    it { is_expected.to include("standard", "json", "one_line", "logfmt") }
    it { is_expected.not_to include("default", "base") }
  end

  describe ".logger" do
    subject { logger }

    it { is_expected.to be_a(SemanticLogger::Logger) }
    its(:name) { is_expected.to eq("Importer") }
  end

  describe "#run" do
    it { expect(logging.run { :done }).to eq(:done) }

    context "logging to the IO" do
      before { logging.run { logger.info("Imported", count: 3) } }

      it { expect(io.string).to match(/ I \[.*\] Importer -- Imported -- \{count: 3\}/) }
      it { expect(SemanticLogger.appenders).to be_empty }
      it { expect(SemanticLogger.default_level).to eq(:info) }
    end

    context "below the level" do
      before { logging.run { logger.debug("noise") } }

      it { expect(io.string).to be_empty }
    end

    context "at debug" do
      let(:level) { "debug" }

      before { logging.run { logger.debug("noise") } }

      it { expect(io.string).to include("Importer -- noise") }
      it { expect(SemanticLogger.default_level).to eq(:info) }
    end

    context "as JSON" do
      let(:format) { "json" }

      before { logging.run { logger.warn("careful") } }

      it { expect(JSON.parse(io.string)).to include("name" => "Importer", "message" => "careful", "level" => "warn") }
    end

    context "to a file" do
      let(:tmp) { Dir.mktmpdir }
      let(:target) { File.join(tmp, "run.log") }

      before { logging.run { logger.error("failed") } }
      after { FileUtils.rm_rf(tmp) }

      it { expect(File.read(target)).to include("Importer -- failed") }
    end

    context "without a target" do
      let(:target) { nil }

      before { logging.run { logger.error("failed") } }

      it { expect(io.string).to be_empty }
      it { expect(SemanticLogger.appenders).to be_empty }
    end

    it "refuses an unknown level before running anything" do
      expect { described_class.new("-", io: io, level: "loud", format: "standard") }.to raise_error(ArgumentError, /log level/)
    end
  end

  # Code a TracePoint runs is invisible to coverage, so .record is also called directly here.
  describe ".record" do
    subject(:frames) { described_class.locals(recorder.error) }

    let(:recorder) do
      Class.new do
        attr_reader :error

        def record(amount)
          @error = ArgumentError.new("bad")
          Dry::CLI::UI::Logging.record(error)
          self
        end

        def bare = Dry::CLI::UI::Logging.record(error)
      end.new
    end

    context "for a new exception" do
      before { recorder.record(42) }

      it { expect(frames.first).to include(locals: { amount: "42" }) }
      it { expect(frames).to all(satisfy { it[:locals].any? }) }
    end

    context "for one already recorded" do
      before { recorder.record(42).bare }

      it { expect(frames.first).to include(locals: { amount: "42" }) }
    end

    context "for a value too long to keep whole" do
      before { recorder.record("x" * 500) }

      it { expect(frames.first[:locals][:amount]).to eq("\"#{'x' * 199}...") }
    end

    context "for a value that cannot be inspected" do
      before { recorder.record(Class.new { def inspect = raise("no") }.new) }

      it { expect(frames.first[:locals][:amount]).to eq("#<RuntimeError from inspect>") }
    end

    context "while already recording on this thread" do
      before do
        Thread.current[:dry_cli_ui_recording] = true
        recorder.record(42)
      ensure
        Thread.current[:dry_cli_ui_recording] = nil
      end

      it { is_expected.to be_nil }
    end
  end

  describe "local variables" do
    subject(:frames) { described_class.locals(caught[:error]) }

    let(:level) { "debug" }

    context "of an exception raised at debug" do
      before do
        logging.run { worker.again(42) }
      rescue ArgumentError => caught[:error]
      end

      it { expect(frames.first).to include(frame: a_string_ending_with("logging_spec.rb:#{worker.method(:fail_with).source_location.last}"), locals: { amount: "42" }) }
      it { expect(frames).to all(satisfy { it[:locals].any? }) }
      it { expect(frames.map { it[:frame] }).to all(exclude("lib/dry/cli/ui/")) }
    end

    context "of an exception raised deep in the stack" do
      before do
        logging.run { worker.deep(40) }
      rescue RuntimeError => caught[:error]
      end

      it { expect(frames.size).to eq(described_class::FRAME_LIMIT) }
    end

    context "too long to keep whole" do
      before do
        logging.run { worker.fail_with("x" * 500) }
      rescue ArgumentError => caught[:error]
      end

      it { expect(frames.first[:locals][:amount]).to eq("\"#{'x' * 199}...") }
    end

    context "that cannot be inspected" do
      let(:value) { Class.new { def inspect = raise("no") }.new }

      before do
        logging.run { worker.fail_with(value) }
      rescue ArgumentError, RuntimeError => caught[:error]
      end

      it { expect(frames.first[:locals][:amount]).to eq("#<RuntimeError from inspect>") }
    end

    context "of an exception raised at info" do
      let(:level) { "info" }

      before do
        logging.run { worker.fail_with(1) }
      rescue ArgumentError => caught[:error]
      end

      it { is_expected.to be_nil }
    end

    context "of an exception raised after the block" do
      before do
        logging.run { nil }
        worker.fail_with(1)
      rescue ArgumentError => caught[:error]
      end

      it { is_expected.to be_nil }
    end
  end
end
