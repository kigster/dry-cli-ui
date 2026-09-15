# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe Dry::CLI::UI do
  it { expect(Dry::CLI::UI::VERSION).to match(/\A\d+\.\d+\.\d+/) }
  it { expect(Dry::CLI::UI::NonInteractiveError.ancestors).to include(Dry::CLI::UI::Error, StandardError) }

  describe "loading" do
    subject(:loaded) do
      script = 'require "dry-cli-ui"; Class.new { include Dry::CLI::UI }; ' \
               'print $LOADED_FEATURES.grep(%r{/(tty-\w+|pastel|dry/cli/ui/console)}).inspect'
      Open3.capture2(RbConfig.ruby, "-I", File.join(PROJECT_ROOT, "lib"), "-e", script).first
    end

    it "loads no TTY toolkit gem until the console is used" do
      expect(loaded).to eq("[]")
    end
  end

  describe ".configure" do
    it "yields the process-wide configuration and returns it" do
      returned = described_class.configure { it.bar_format = :classic }
      expect(returned).to be(described_class.config)
      expect(described_class.config.bar_format).to eq(:classic)
    end

    it "runs a block without arguments against the configuration" do
      described_class.configure { spinner_format :pong }
      expect(described_class.config.spinner_format).to eq(:pong)
    end

    it "is what a console draws with unless it is given another" do
      described_class.configure { bar_format(complete: "#", incomplete: ".") }
      err = FakeTTY.new
      allow(TTY::Screen).to receive(:height).and_return(24)
      Dry::CLI::UI::Console.new(err: err, env: {}, width: 60).multi_progress("Go") do |m|
        m.progress("a", total: 2) { |bar| bar.advance && sleep(0.15) }
      end
      expect(plain(err.string)).to include("[#")
    end
  end

  describe ".reset!" do
    it "forgets every process-wide setting" do
      described_class.configure { bar_format :classic }
      described_class.reset!
      expect(described_class.config.bar_format).to eq(complete: "◼", incomplete: " ")
    end
  end

  describe "#ui" do
    context "in a dry-cli command run with its own streams" do
      let(:command) do
        Class.new(Dry::CLI::Command) do
          include Dry::CLI::UI

          def call(**)
            ui.success "all good"
            ui.error "oh no"
          end
        end
      end
      let(:out) { StringIO.new }
      let(:err) { StringIO.new }

      before { Dry::CLI.new(command).call(arguments: [], out: out, err: err) }

      it { expect(out.string).to include("Success", "all good").and exclude("oh no") }
      it { expect(err.string).to include("Error", "oh no").and exclude("all good") }
    end

    context "in a plain object" do
      subject(:host) { Class.new { include Dry::CLI::UI }.new }

      its(:ui) { is_expected.to be_a(Dry::CLI::UI::Console) }
      it { expect(host.ui).to be(host.ui) }

      it "writes to $stdout" do
        expect { host.ui.info("hello") }.to output(/hello/).to_stdout
      end

      it "writes diagnostics to $stderr" do
        expect { host.ui.warn("careful") }.to output(/careful/).to_stderr
      end
    end

    context "in a dry-cli command that was never run" do
      subject(:command) { Class.new(Dry::CLI::Command) { include Dry::CLI::UI }.new }

      it "falls back to $stdout" do
        expect { command.ui.info("hello") }.to output(/hello/).to_stdout
      end
    end
  end
end
