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

    context "with reserved flags declared" do
      subject(:loaded) do
        script = 'require "dry/cli"; require "dry-cli-ui"; ' \
                 "Class.new(Dry::CLI::Command) { include Dry::CLI::UI; extend Dry::CLI::UI::Flags; flags :yes, :output, :log }; " \
                 'print $LOADED_FEATURES.grep(%r{/(tty-\w+|pastel|semantic_logger|binding_of_caller)}).inspect'
        Open3.capture2(RbConfig.ruby, "-I", File.join(PROJECT_ROOT, "lib"), "-e", script).first
      end

      it "loads neither SemanticLogger nor binding_of_caller until a command logs" do
        expect(loaded).to eq("[]")
      end
    end
  end

  it { expect(described_class.started_at).to be_a(Time).and be <= Time.now }

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
      console = Dry::CLI::UI::Console.new(err: err, env: {}, width: 60)
      allow(TTY::Screen).to receive(:height).and_return(24)
      console.multi_progress("Go") do |m|
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
    context "in a dry-cli command run with its own streams", if: DRY_CLI_PUBLIC_STREAMS do
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

      before { Dry::CLI.new(command).call(arguments: [], stdout: out, stderr: err) }

      it { expect(out.string).to include("Success", "all good").and exclude("oh no") }
      it { expect(err.string).to include("Error", "oh no").and exclude("all good") }
    end

    context "in a dry-cli command reading a prompt's answer", if: DRY_CLI_PUBLIC_STREAMS do
      let(:command) do
        Class.new(Dry::CLI::Command) do
          include Dry::CLI::UI

          def call(**) = ui.info(ui.prompt("Name?"))
        end
      end
      let(:out) { StringIO.new }

      before do
        Dry::CLI.new(command).call(arguments: [], stdin: StringIO.new("Ada\n"), stdout: out, stderr: StringIO.new)
      end

      it { expect(plain(out.string)).to include("Ada") }
    end

    context "in a dry-cli command registered as an instance, called twice", if: DRY_CLI_PUBLIC_STREAMS do
      let(:instance) do
        Class.new(Dry::CLI::Command) do
          include Dry::CLI::UI

          def call(**) = ui.info("hello")
        end.new
      end
      let(:outputs) { [StringIO.new, StringIO.new] }

      before do
        outputs.each { |io| Dry::CLI.new(instance).call(arguments: [], stdout: io, stderr: StringIO.new) }
      end

      it "writes each call to that call's stream" do
        expect(outputs.map { plain(_1.string) }).to all(include("hello"))
      end
    end

    context "in a dry-cli command run in-process by a launcher", if: DRY_CLI_PUBLIC_STREAMS do
      let(:launcher) do
        Dry::CLI::Launcher[
          Class.new(Dry::CLI::Command) do
            include Dry::CLI::UI

            def call(**)
              ui.success "done"
              ui.warn "careful"
            end
          end
        ]
      end
      let(:out) { StringIO.new }
      let(:err) { StringIO.new }
      let(:kernel) { Class.new { attr_reader :status; def exit(status) = @status = status }.new }

      before { launcher.new([], StringIO.new, out, err, kernel).execute! }

      it { expect(plain(out.string)).to include("done") }
      it { expect(plain(err.string)).to include("careful") }
      it { expect(kernel.status).to eq(0) }
    end

    context "in a command with options of its own", if: DRY_CLI_PUBLIC_STREAMS do
      subject(:command) do
        Class.new(Dry::CLI::Command) do
          include Dry::CLI::UI

          private def ui_options = { box_width: 30 }
        end.new(stdout: StringIO.new)
      end

      it { expect(command.ui.send(:box_width)).to eq(30) }
    end

    context "when a dry-cli command's own streams render dry-cli styles", if: DRY_CLI_PUBLIC_STREAMS do
      subject(:command) { Class.new(Dry::CLI::Command) { include Dry::CLI::UI }.new(stdout: io) }

      let(:io) { StringIO.new }

      it "writes to the IO beneath them" do
        command.ui.info("hello")
        expect(io.string).to include("hello")
      end
    end

    context "in a dry-cli 1.4 command run with its own streams", unless: DRY_CLI_PUBLIC_STREAMS do
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

    context "in an object with protected out and err, as dry-cli 1.4 gives a command" do
      subject(:host) do
        Class.new do
          include Dry::CLI::UI

          def initialize(out, err) = (@out, @err = out, err)

          protected

          attr_reader :out, :err
        end.new(out, err)
      end

      let(:out) { StringIO.new }
      let(:err) { StringIO.new }

      it "writes results to out and diagnostics to err" do
        host.ui.info("hello")
        host.ui.warn("careful")
        expect([plain(out.string), plain(err.string)]).to match([/hello/, /careful/])
      end

      context "before it was run" do
        let(:out) { nil }
        let(:err) { nil }

        it "falls back to $stdout" do
          expect { host.ui.info("hello") }.to output(/hello/).to_stdout
        end
      end
    end

    context "in a plain object" do
      subject(:host) { Class.new { include Dry::CLI::UI }.new }

      its(:ui) { is_expected.to be_a(Dry::CLI::UI::Console) }
      it { expect(host.ui).to be(host.ui) }

      it "builds a new console when $stdout changes" do
        first = host.ui
        original = $stdout
        $stdout = StringIO.new
        expect(host.ui).not_to be(first)
      ensure
        $stdout = original
      end

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
