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
      end

      # The console this command presents through. Writes to the command's own
      # `out` and `err` when dry-cli has set them, and to `$stdout` and
      # `$stderr` otherwise.
      #
      # Override it to configure the console:
      #
      # @example
      #   def ui = @ui ||= Dry::CLI::UI::Console.new(box_width: 72)
      #
      # @return [Dry::CLI::UI::Console]
      def ui
        @ui ||= Console.new(
          out: (respond_to?(:out, true) && __send__(:out)) || $stdout,
          err: (respond_to?(:err, true) && __send__(:err)) || $stderr
        )
      end
    end
  end
end
