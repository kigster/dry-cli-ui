# frozen_string_literal: true

require_relative "ui/version"

# The dry-rb namespace, which dry-cli lives in. This gem is not part of dry-rb.
module Dry
  class CLI
    # Runtime presentation for Dry::CLI commands: boxes, status lines,
    # spinners, progress bars, task trees, tables and prompts.
    #
    # Include it in a command, or in the base class every command inherits
    # from, and call {#ui}. Everything else loads the first time it is used,
    # so including the module costs a command nothing at boot.
    #
    # @example
    #   class Import < Dry::CLI::Command
    #     include Dry::CLI::UI
    #
    #     def call(**)
    #       ui.spinner("Loading YAML") { load_rules }
    #       ui.success "Imported #{rules.size} rules"
    #     rescue => e
    #       ui.error("Import failed", e.message)
    #     end
    #   end
    module UI
      # Base class for every error this gem raises.
      class Error < StandardError; end

      # Raised when a prompt needs an answer, no default was given, and the
      # input stream is exhausted.
      class NonInteractiveError < Error; end

      autoload :Configuration, File.expand_path("ui/configuration", __dir__)
      autoload :Console, File.expand_path("ui/console", __dir__)
      autoload :Duration, File.expand_path("ui/duration", __dir__)
      autoload :Line, File.expand_path("ui/line", __dir__)
      autoload :Stop, File.expand_path("ui/stop", __dir__)
      autoload :StatusBar, File.expand_path("ui/status_bar", __dir__)
      autoload :Terminal, File.expand_path("ui/terminal", __dir__)
      autoload :Theme, File.expand_path("ui/theme", __dir__)
      autoload :Widgets, File.expand_path("ui/widgets", __dir__)

      class << self
        # Make process-wide settings. A block taking an argument receives the
        # configuration; any other block runs against it.
        #
        # @example
        #   Dry::CLI::UI.configure do
        #     spinner_format :dots
        #     bar_format :box
        #     bar_color :cyan
        #   end
        #
        # @return [Configuration]
        def configure(&block)
          block.arity == 1 ? yield(config) : config.instance_eval(&block)
          config
        end

        # @return [Configuration] the process-wide settings
        def config
          @config ||= Configuration.new
        end

        # Forget every process-wide setting.
        #
        # @return [void]
        def reset!
          @config = nil
        end

        # The IO beneath a dry-cli stream, or the stream itself when it is not one.
        #
        # Asks for the class rather than for `raw`, which `io/console` also defines on every IO, to
        # put a terminal into raw mode.
        #
        # @param stream [IO, Dry::CLI::Stream]
        # @return [IO]
        def raw(stream)
          defined?(Dry::CLI::Stream) && stream.is_a?(Dry::CLI::Stream) ? stream.raw : stream
        end
      end

      # The console this command presents through.
      #
      # In a dry-cli command it writes to the command's own `stdout` and `stderr`, and reads prompt
      # answers from its `stdin`: the streams the CLI was called with. Under dry-cli 1.4 and
      # earlier, which give a command only `out` and `err`, it writes to those and reads `$stdin`.
      # Anywhere else it uses `$stdout`, `$stderr` and `$stdin`.
      #
      # The console is built again whenever those streams change. A command registered as an
      # instance is used for every call to its CLI, each time with that call's streams, as when a
      # test suite runs the CLI in-process with a StringIO per test.
      #
      # Configure the console by overriding {#ui_options}.
      #
      # @return [Dry::CLI::UI::Console]
      def ui
        streams = ui_streams
        @ui = nil unless @ui_streams && streams.all? { |name, io| @ui_streams[name].equal?(io) }
        @ui_streams = streams
        @ui ||= Console.new(**streams, **ui_options)
      end

      private

      # The streams {#ui} presents through, as keywords for {Console#initialize}.
      #
      # A dry-cli command gives its own public `stdout`, `stderr` and `stdin`. Its output streams
      # render dry-cli's own styles; the console writes to the IO beneath them, since it decides
      # colour for itself.
      #
      # @return [Hash{Symbol => IO}] `out:`, `err:` and `input:`
      def ui_streams
        {
          out: UI.raw(ui_stream(:stdout, :out) || $stdout),
          err: UI.raw(ui_stream(:stderr, :err) || $stderr),
          input: respond_to?(:stdin) ? stdin : $stdin
        }
      end

      # One of the command's output streams: the public one, or the protected one dry-cli 1.4 and
      # earlier set on a command it runs.
      #
      # @param name [Symbol] the public reader, `:stdout` or `:stderr`
      # @param legacy_name [Symbol] the protected reader, `:out` or `:err`
      # @return [IO, Dry::CLI::Stream, nil] nil when the command has neither, or was never run
      def ui_stream(name, legacy_name)
        return public_send(name) if respond_to?(name)

        __send__(legacy_name) if respond_to?(legacy_name, true)
      end

      # Options for {Console#initialize} other than its streams. Override it to configure the
      # console {#ui} builds.
      #
      # @example
      #   def ui_options = { box_width: 72 }
      #
      # @return [Hash{Symbol => Object}]
      def ui_options
        {}
      end
    end
  end
end
