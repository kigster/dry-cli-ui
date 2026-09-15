# frozen_string_literal: true

require "tty-spinner"

module Dry
  class CLI
    module UI
      module Widgets
        # Shows that a block is running, then how it ended and how long it took.
        #
        # On an animated terminal the spinner turns until the block returns
        # and is replaced by the outcome line. Anywhere else it prints
        # `Label...` before the block and the outcome line after it.
        #
        # The block is given a {Line}. Its detail is drawn after the label
        # while the spinner turns, and {Line#fail} ends it as a failure
        # without raising.
        class Spinner
          # @param terminal [Terminal]
          # @param clock [#call] returns monotonic seconds
          # @param config [Configuration] where the frames come from
          def initialize(terminal, clock:, config: UI.config)
            @terminal = terminal
            @clock = clock
            @config = config
          end

          # Runs the block under a spinner.
          #
          # @param label [String]
          # @yieldparam line [Line] reports on the work while it runs
          # @return [Object] whatever the block returns
          # @raise [Exception] whatever the block raises, after marking the spinner failed
          def run(label, &job)
            spinner = nil
            line = Line.new { |text| spinner&.update(detail: text.empty? ? "" : " #{text}") }
            started = clock.call
            terminal.started(line, label)
            spinner = start(label)
            ok = false
            result = Line.call(job, line)
            ok = !line.failed?
            result
          ensure
            spinner&.stop
            terminal.finished(line, ok)
            terminal.puts(Outcome.line(terminal, ok ? :done : :failed, line.summary(label), clock.call - started))
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @return [Configuration]
          attr_reader :config

          # @param label [String]
          # @return [TTY::Spinner, nil] the running spinner, or nil when not animating
          def start(label)
            unless terminal.animated?
              terminal.puts("#{label}...")
              return
            end

            TTY::Spinner.new(":spinner #{label}:detail", output: terminal.io, frames: config.spinner_frames,
                                                         interval: 1.0 / config.spinner_frame_seconds,
                                                         hide_cursor: true, clear: true)
                        .tap { |spinner| spinner.update(detail: "") }
                        .tap(&:auto_spin)
          end
        end
      end
    end
  end
end
