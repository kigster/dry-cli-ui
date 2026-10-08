# frozen_string_literal: true

require "dry/cli"

module Dry
  class CLI
    module UI
      # The reserved flags: options that mean the same thing in every CLI built on this gem.
      #
      # | Flag | Long                  | Meaning                                                    |
      # | ---- | --------------------- | ---------------------------------------------------------- |
      # | `-n` | `--dry-run`           | change nothing, print what would happen                    |
      # | `-y` | `--yes`               | skip every interactive prompt                              |
      # | `-o` | `--output [FILE]`     | write the command's report to FILE, in colour              |
      # | `-l` | `--log [FILE]`        | log to FILE through SemanticLogger                         |
      # | `-L` | `--log-level LEVEL`   | debug, info, warn, error or fatal (info by default)        |
      # |      | `--log-format FORMAT` | standard (the default), json, or another SemanticLogger formatter |
      #
      # Extend a command class with it and name the flags it takes. `:log` brings `-L` and
      # `--log-format` with it. The options reach `call` as `dry_run:`, `yes:`, `output:`, `log:`,
      # `log_level:` and `log_format:`; hand them to {Console#with_flags}, or to {Console#output},
      # {Console#logging} and {Console#confirm} one at a time.
      #
      # dry-cli gives every string option a required value, so on its own it rejects a bare `-o`.
      # Loading this module prepends {Hook} onto `Dry::CLI`, which rewrites a bare `-o`,
      # `--output`, `-l` or `--log` into an empty value (see {.arguments}) for the commands that
      # extend this module, and nothing else. An empty value means "the default file".
      #
      # @example
      #   class Export < Dry::CLI::Command
      #     include Dry::CLI::UI
      #     extend Dry::CLI::UI::Flags
      #
      #     flags :dry_run, :yes, :output, :log
      #   end
      module Flags
        # Every option each reserved flag declares, as arguments to dry-cli's `option`.
        OPTIONS = {
          dry_run: {
            dry_run: { type: :flag, default: false, aliases: ["-n"], desc: "Change nothing; print what would happen" }
          },
          yes: {
            yes: { type: :flag, default: false, aliases: ["-y"], desc: "Answer yes to every prompt" }
          },
          output: {
            output: { aliases: ["-o"], desc: "Write the report to FILE: log/ by default, - for STDOUT" }
          },
          log: {
            log: { aliases: ["-l"], desc: "Log to FILE: log/ by default, - for STDOUT" },
            log_level: { aliases: ["-L"], default: "info", values: %w[debug info warn error fatal],
                         desc: "Log level" },
            log_format: { default: "standard", desc: "Log format: standard, json, or another SemanticLogger formatter" }
          }
        }.freeze

        # The reserved flags that take an optional file.
        OPTIONAL_VALUES = %i[output log].freeze

        # The switches {.arguments} rewrites unless told otherwise.
        SWITCHES = %w[-o --output -l --log].freeze

        # Gives a bare switch an empty value, so that dry-cli, which requires one, accepts it.
        #
        # A switch is bare when it is last, or when the next argument starts with `-` and is not
        # exactly `-`. `-o=x`, `--output=x`, `-ox`, `-o x` and `-o -` are left alone, as is
        # everything after `--`.
        #
        # @example
        #   Dry::CLI::UI::Flags.arguments(%w[export -o --verbose])  # => ["export", "-o", "", "--verbose"]
        #
        # @param argv [Array<String>] the command line
        # @param switches [Array<String>] the switches that take an optional value
        # @return [Array<String>] a new array; argv is not changed
        def self.arguments(argv, switches: SWITCHES)
          ended = false
          argv.each_with_index.flat_map do |token, index|
            ended ||= token == "--"
            bare = !ended && switches.include?(token) && bare_before?(argv[index + 1])
            bare ? [token, ""] : [token]
          end
        end

        # Whether a switch followed by this argument has no value.
        #
        # @param following [String, nil] the next argument, nil at the end of the line
        # @return [Boolean]
        def self.bare_before?(following)
          following.nil? || (following.start_with?("-") && following != "-")
        end
        private_class_method :bare_before?

        # The switches of a command's options that take an optional file, as typed on a command
        # line: `--output` and each of its aliases, and the same for `--log`.
        #
        # @param command [Class] a command class extended with this module
        # @return [Array<String>]
        def self.switches(command)
          command.options.select { OPTIONAL_VALUES.include?(it.name.to_sym) }.flat_map do |option|
            names = [option.name.to_s.tr("_", "-"), *option.aliases.map { it.delete_prefix("-").delete_prefix("-") }]
            names.map { it.size == 1 ? "-#{it}" : "--#{it}" }
          end
        end

        # Declares reserved flags as options of this command.
        #
        # @param names [Array<Symbol>] any of `:dry_run`, `:yes`, `:output` and `:log`
        # @return [Array<Symbol>] the names
        # @raise [ArgumentError] when a name is not a reserved flag; nothing is declared
        def flags(*names)
          unknown = names - OPTIONS.keys
          raise ArgumentError, "unknown flag #{unknown.map(&:inspect).join(', ')}, expected any of #{OPTIONS.keys}" if unknown.any?

          names.each { |name| OPTIONS.fetch(name).each { |option_name, settings| option(option_name, settings) } }
          names
        end

        # Prepended onto `Dry::CLI` when {Flags} loads. It rewrites the arguments of a command that
        # extends {Flags} with {Flags.arguments}, and records on a command that includes {UI} the
        # names it was called by, which name its default report and log files.
        #
        # @api private
        module Hook
          private

          # @param command [Class, Dry::CLI::Command] the command dry-cli resolved
          # @param arguments [Array<String>] the arguments after the command's names
          # @param names [Array<String>] the names the command was called by
          # @return [Array(Dry::CLI::Command, Hash)] the command to call and its arguments
          def parse(command, arguments, names)
            klass = command.is_a?(Class) ? command : command.class
            arguments = Flags.arguments(arguments, switches: Flags.switches(klass)) if klass.is_a?(Flags)
            result = super
            instance, = result
            instance.instance_variable_set(:@ui_command_names, names) if instance.is_a?(UI)
            result
          end
        end

        CLI.prepend(Hook)
      end
    end
  end
end
