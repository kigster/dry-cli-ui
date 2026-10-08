# frozen_string_literal: true

require "semantic_logger"

module Dry
  class CLI
    module UI
      # SemanticLogger set up from the reserved `-l`, `-L` and `--log-format` flags, for as long as
      # a block runs. See {Console#logging}.
      #
      # At level `debug` it also records, for every exception raised while the block runs, the
      # local variables of each frame on the stack where it was raised. {Console#log_exception}
      # logs them with the exception. Recording them costs time, which is why it happens at
      # `debug` only.
      class Logging
        # The levels `-L` takes.
        LEVELS = %w[debug info warn error fatal].freeze

        # Formats named differently here than in SemanticLogger.
        FORMATS = { "standard" => :default }.freeze

        # The most characters of a local variable's `inspect` kept.
        INSPECT_LIMIT = 200

        # The most frames whose local variables are kept for one exception.
        FRAME_LIMIT = 25

        # Frames in this gem's own files, which are left out of what is recorded.
        OWN_FILES = "#{File.expand_path(__dir__)}/".freeze

        # Local variables recorded for each exception, keyed by the exception.
        LOCALS = ::ObjectSpace::WeakMap.new

        class << self
          # Checks a level name.
          #
          # @param name [String, Symbol]
          # @return [Symbol]
          # @raise [ArgumentError] when it is not one of {LEVELS}
          def level(name)
            return name.to_sym if LEVELS.include?(name.to_s)

            raise ArgumentError, "unknown log level #{name.to_s.inspect}, expected one of #{LEVELS.join(', ')}"
          end

          # Builds a SemanticLogger formatter from its name: `standard` for SemanticLogger's default,
          # one line per entry, or the name of any formatter SemanticLogger has, such as `json`,
          # `color` or `logfmt`.
          #
          # @param name [String, Symbol]
          # @return [#call] the formatter
          # @raise [ArgumentError] when SemanticLogger has no formatter of that name
          def formatter(name)
            SemanticLogger::Formatters.factory(FORMATS.fetch(name.to_s) { name.to_s.to_sym })
          rescue ArgumentError
            raise ArgumentError, "unknown log format #{name.to_s.inspect}, expected one of #{formats.join(', ')}", cause: nil
          end

          # @return [Array<String>] the names {.formatter} takes
          def formats
            names = (SemanticLogger::Formatters.constants - [:Base]).map do |constant|
              constant.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
            end
            (FORMATS.keys + names - FORMATS.values.map(&:to_s)).sort
          end

          # A SemanticLogger logger.
          #
          # @param name [String]
          # @return [SemanticLogger::Logger]
          def logger(name)
            SemanticLogger[name]
          end

          # The local variables recorded for an exception raised while logging at `debug`.
          #
          # @param exception [Exception]
          # @return [Array<Hash{Symbol => Object}>, nil] one entry per frame, innermost first, each
          #   with its `frame` and `locals`; nil when nothing was recorded
          def locals(exception)
            LOCALS[exception]
          end

          # Records the local variables of the frames on the stack, for an exception being raised.
          # Keeps what was recorded where the exception was first raised.
          #
          # @param exception [Exception]
          # @return [void]
          def record(exception)
            return if LOCALS.key?(exception) || Thread.current[:dry_cli_ui_recording]

            Thread.current[:dry_cli_ui_recording] = true
            begin
              LOCALS[exception] = frames(binding.callers)
            ensure
              Thread.current[:dry_cli_ui_recording] = nil
            end
          end

          private

          # @param bindings [Array<Binding>] the stack, innermost first
          # @return [Array<Hash{Symbol => Object}>]
          def frames(bindings)
            bindings.reject { it.source_location.first.start_with?(OWN_FILES) }.filter_map do |frame|
              names = frame.local_variables
              next if names.empty?

              { frame: frame.source_location.join(":"), locals: names.to_h { [it, describe(frame.local_variable_get(it))] } }
            end.first(FRAME_LIMIT)
          end

          # @param value [Object]
          # @return [String] its `inspect`, cut to {INSPECT_LIMIT} characters
          def describe(value)
            text = value.inspect
            text.length > INSPECT_LIMIT ? "#{text[0, INSPECT_LIMIT]}..." : text
          rescue StandardError => e
            "#<#{e.class} from inspect>"
          end
        end

        # @param target [String, nil] a file, `-` for `io`, or nil for no log
        # @param io [IO] where `-` logs
        # @param level [String, Symbol] one of {LEVELS}
        # @param format [String, Symbol] see {.formatter}
        # @raise [ArgumentError] for an unknown level or format
        def initialize(target, io:, level:, format:)
          @target = target
          @io = io
          @level = Logging.level(level)
          @formatter = Logging.formatter(format)
        end

        # Adds the appender, sets the level, and runs the block. Afterwards flushes and removes the
        # appender and puts the level back.
        #
        # @yield
        # @return [Object] whatever the block returns
        def run(&)
          return yield if target.nil?

          start
          yield
        ensure
          stop
        end

        private

        # @return [String, nil]
        attr_reader :target

        # @return [IO]
        attr_reader :io

        # @return [Symbol]
        attr_reader :level

        # @return [#call]
        attr_reader :formatter

        # @return [void]
        def start
          destination = target == "-" ? { io: io } : { file_name: target }
          @appender = SemanticLogger.add_appender(**destination, formatter: formatter)
          @previous_level = SemanticLogger.default_level
          SemanticLogger.default_level = level
          trace if level == :debug
        end

        # @return [void]
        def trace
          require "binding_of_caller"
          @trace = TracePoint.new(:raise) { |point| Logging.record(point.raised_exception) }
          @trace.enable
        end

        # @return [void]
        def stop
          return unless @appender

          @trace&.disable
          SemanticLogger.flush
          SemanticLogger.remove_appender(@appender)
          SemanticLogger.default_level = @previous_level
          @appender = nil
        end
      end
    end
  end
end
