# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Flags do
  describe ".arguments" do
    {
      %w[-o] => ["-o", ""],
      %w[--output] => ["--output", ""],
      %w[-l --verbose] => ["-l", "", "--verbose"],
      %w[--log -o] => ["--log", "", "-o", ""],
      %w[-o --] => ["-o", "", "--"],
      %w[-o x] => %w[-o x],
      %w[-o -] => %w[-o -],
      %w[-o=x] => %w[-o=x],
      %w[--output=x] => %w[--output=x],
      %w[-ox] => %w[-ox],
      %w[-- -o] => %w[-- -o],
      %w[a b] => %w[a b]
    }.each do |argv, expected|
      context "given #{argv.join(' ')}" do
        subject { described_class.arguments(argv) }

        it { is_expected.to eq(expected) }
      end
    end

    context "with switches of its own" do
      subject { described_class.arguments(%w[-f -o], switches: %w[-f]) }

      it { is_expected.to eq(["-f", "", "-o"]) }
    end

    context "given an array it must not change" do
      let(:argv) { %w[-o] }

      before { described_class.arguments(argv) }

      it { expect(argv).to eq(%w[-o]) }
    end
  end

  describe "#flags" do
    subject(:command) { Class.new(Dry::CLI::Command) { extend Dry::CLI::UI::Flags } }

    context "with every flag" do
      before { command.flags(:dry_run, :yes, :output, :log) }

      it { expect(command.options.map(&:name)).to eq(%i[dry_run yes output log log_level log_format]) }
      it { expect(command.options.to_h { [it.name, it.default] }).to include(dry_run: false, yes: false, log_level: "info", log_format: "standard") }
      it { expect(command.options.to_h { [it.name, it.aliases] }).to include(dry_run: ["-n"], yes: ["-y"], output: ["-o"], log: ["-l"], log_level: ["-L"]) }
      it { expect(described_class.switches(command)).to eq(%w[--output -o --log -l]) }
    end

    it { expect(command.flags(:yes)).to eq([:yes]) }

    it "refuses a name that is not a reserved flag, declaring nothing" do
      expect { command.flags(:yes, :verbose) }
        .to raise_error(ArgumentError, /unknown flag :verbose/).and avoid_changing { command.options.size }
    end
  end

  describe "through dry-cli" do
    let(:command) do
      Class.new(Dry::CLI::Command) do
        include Dry::CLI::UI
        extend Dry::CLI::UI::Flags

        flags :dry_run, :yes, :output, :log

        class << self
          attr_accessor :received, :basename
        end

        def call(**options)
          self.class.received = options
          self.class.basename = ui.send(:invocation).basename
        end
      end
    end
    let(:registered) { command }
    let(:registry) { Module.new { extend Dry::CLI::Registry } }
    let(:cli) { Dry::CLI.new(registry) }
    let(:out) { StringIO.new }
    let(:err) { StringIO.new }
    let(:argv) { [] }
    let(:line) { ["generate", "text", *argv] }

    before do
      registry.register("generate text", registered)
      call_cli(cli, line, out: out, err: err)
    end

    it { expect(command.received).to include(dry_run: false, yes: false, log_level: "info", log_format: "standard") }
    it { expect(command.received).not_to include(:output, :log) }
    it { expect(command.basename).to eq("rspec-generate-text") }

    {
      %w[-o] => { output: "" },
      %w[--output -l] => { output: "", log: "" },
      %w[-n -y -o -l -L debug --log-format json] => {
        dry_run: true, yes: true, output: "", log: "", log_level: "debug", log_format: "json"
      },
      %w[--dry-run --yes -o report.txt --log run.log] => { dry_run: true, yes: true, output: "report.txt", log: "run.log" },
      %w[-o - -l -] => { output: "-", log: "-" }
    }.each do |given, expected|
      context "given #{given.join(' ')}" do
        let(:argv) { given }

        it { expect(command.received).to include(expected) }
      end
    end

    context "with the command registered as an instance" do
      let(:registered) { command.new }
      let(:argv) { %w[-o] }

      it { expect(command.received).to include(output: "") }
      it { expect(command.basename).to eq("rspec-generate-text") }
    end

    context "as the only command of a CLI" do
      let(:cli) { Dry::CLI.new(command) }
      let(:line) { %w[-l] }

      it { expect(command.received).to include(log: "") }
      it { expect(command.basename).to eq("rspec") }
    end
  end

  describe "a command that does not extend it" do
    let(:command) do
      Class.new(Dry::CLI::Command) do
        include Dry::CLI::UI

        option :name, aliases: ["-o"]

        class << self
          attr_accessor :received, :basename
        end

        def call(**options)
          self.class.received = options
          self.class.basename = ui.send(:invocation).basename
        end
      end
    end
    let(:registry) { Module.new { extend Dry::CLI::Registry } }

    before do
      allow(described_class).to receive(:arguments).and_call_original
      registry.register("plain", command)
      call_cli(Dry::CLI.new(registry), %w[plain -o x], out: StringIO.new, err: StringIO.new)
    end

    it { expect(described_class).not_to have_received(:arguments) }
    it { expect(command.received).to include(name: "x") }
    it { expect(command.basename).to eq("rspec-plain") }
  end

  describe "a command without the UI" do
    let(:command) do
      Class.new(Dry::CLI::Command) do
        class << self
          attr_accessor :called
        end

        def call(**) = self.class.called = true
      end
    end

    before { call_cli(Dry::CLI.new(command), [], out: StringIO.new, err: StringIO.new) }

    it { expect(command.called).to be(true) }
    it { expect(command.new.instance_variable_defined?(:@ui_command_names)).to be(false) }
  end
end
