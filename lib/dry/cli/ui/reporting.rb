# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # The part of {Console} behind the reserved `-o`, `-l`, `-L` and `--log-format` flags (see
      # {Flags}): where a command's report goes, and how it logs.
      module Reporting
        # Sends what the block writes to `out` to the file `-o` named. Tables, boxes and statuses at
        # `info` and `success` land there, in colour; spinners, bars, prompts and warnings stay on
        # `err`. The block is given the IO the report goes to, for writing to it directly.
        #
        # The file's last line says when it was closed, and a line on `err` says where it is.
        #
        # @example
        #   ui.output(output) do |io|
        #     ui.table(rows, header: %w[Rule Count])
        #     io.puts "#{rows.size} rules"
        #   end
        #
        # @param value [String, nil] what `-o` was given: nil without `-o` and `-` for STDOUT, both
        #   meaning the command's own `out`; an empty string for
        #   `log/<executable>-<action>.<YYYY-MM-DD>.<HHMMSS>.log` at the repository root, stamped
        #   with the time the process started; or a path
        # @yieldparam io [IO] where the report goes
        # @return [Object] whatever the block returns
        # @raise [ArgumentError] without a block
        def output(value = nil, &)
          raise ArgumentError, "output needs a block" unless block_given?

          path = invocation.report_path(value)
          return yield(out.io) if path.nil?

          begin
            File.open(path, "w") { |file| write_report(Report.new(file), &) }
          ensure
            notice = "Report written to #{Pathname(path).relative_path_from(invocation.directory)}"
            err.puts(Widgets::Status.line(err, Theme.level(:info), notice))
          end
        end

        # Logs through SemanticLogger to the file `-l` named while the block runs, then flushes and
        # removes the appender. At level `debug` it records the local variables of every frame an
        # exception is raised through, for {#log_exception}.
        #
        # @example
        #   ui.logging(log, level: log_level, format: log_format) do
        #     ui.logger.info("Importing", count: rules.size)
        #   end
        #
        # @param value [String, nil] what `-l` was given: nil for no log; `-` for the command's own
        #   `out`; an empty string for `log/<executable>-<action>.log` at the repository root; or a
        #   path
        # @param level [String, Symbol] `debug`, `info`, `warn`, `error` or `fatal`
        # @param format [String, Symbol] `standard`, `json`, or another SemanticLogger formatter
        # @return [Object] whatever the block returns
        # @raise [ArgumentError] without a block, or for an unknown level or format
        def logging(value, level: "info", format: "standard", &)
          raise ArgumentError, "logging needs a block" unless block_given?

          Logging.new(invocation.log_path(value), io: out.io, level: level, format: format).run(&)
        end

        # Applies the reserved flags a command was called with: {#logging} around {#output}. Takes
        # the whole options hash `call` receives and ignores what it does not use.
        #
        # @example
        #   def call(**options)
        #     ui.with_flags(**options) { |io| ui.table(rows) }
        #   end
        #
        # @param output [String, nil] see {#output}
        # @param log [String, nil] see {#logging}
        # @param log_level [String, Symbol]
        # @param log_format [String, Symbol]
        # @yieldparam io [IO] where the report goes
        # @return [Object] whatever the block returns
        # @raise [ArgumentError] without a block, or for an unknown level or format
        def with_flags(output: nil, log: nil, log_level: "info", log_format: "standard", **, &)
          raise ArgumentError, "with_flags needs a block" unless block_given?

          logging(log, level: log_level, format: log_format) { self.output(output, &) }
        end

        # The command's SemanticLogger logger, named after the command's class. It writes nothing
        # until {#logging} adds an appender.
        #
        # @return [SemanticLogger::Logger]
        def logger
          @logger ||= Logging.logger(invocation.name)
        end

        # Logs an exception with its backtrace and, when it was raised while logging at `debug`,
        # the local variables of each frame it was raised through, as the payload's `locals`.
        #
        # @example
        #   rescue => e
        #     ui.log_exception(e, "Import failed")
        #
        # @param exception [Exception]
        # @param message [String, nil] the exception's message by default
        # @param level [String, Symbol]
        # @return [nil]
        # @raise [ArgumentError] for an unknown level
        def log_exception(exception, message = nil, level: :error)
          locals = Logging.locals(exception)
          logger.public_send(Logging.level(level), message || exception.message, locals && { locals: locals }, exception)
          nil
        end

        private

        # @return [Invocation] how the command was run; describes no command when none was given
        def invocation
          @invocation ||= Invocation.for
        end

        # Points `out` at a report while the block runs, then ends the report with the time.
        #
        # @param report [Report]
        # @yieldparam report [Report]
        # @return [Object] whatever the block returns
        def write_report(report)
          previous = @out
          @out = previous.to(report)
          yield report
        ensure
          @out = previous
          report.puts("Closed at #{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}")
        end
      end
    end
  end
end
