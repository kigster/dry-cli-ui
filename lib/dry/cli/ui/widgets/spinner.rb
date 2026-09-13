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
        class Spinner
          # @param terminal [Terminal]
          # @param clock [#call] returns monotonic seconds
          def initialize(terminal, clock:)
            @terminal = terminal
            @clock = clock
          end

          # Runs the block under a spinner.
          #
          # @param label [String]
          # @yield the work to show progress for
          # @return [Object] whatever the block returns
          # @raise [Exception] whatever the block raises, after marking the spinner failed
          def run(label)
            started = clock.call
            spinner = start(label)
            ok = false
            result = yield
            ok = true
            result
          ensure
            spinner&.stop
            terminal.puts(Outcome.line(terminal, ok ? :done : :failed, label, clock.call - started))
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @param label [String]
          # @return [TTY::Spinner, nil] the running spinner, or nil when not animating
          def start(label)
            unless terminal.animated?
              terminal.puts("#{label}...")
              return
            end

            TTY::Spinner.new(":spinner #{label}", output: terminal.io, format: :dots, hide_cursor: true, clear: true)
                        .tap(&:auto_spin)
          end
        end
      end
    end
  end
end
