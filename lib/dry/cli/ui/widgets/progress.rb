# frozen_string_literal: true

require "tty-progressbar"

module Dry
  class CLI
    module UI
      module Widgets
        # A progress bar with a percentage, a count and an ETA, followed by
        # the outcome line once the block ends.
        #
        # Without an animated terminal it prints `Label...` before the block
        # and the outcome line, with the final count, after it.
        class Progress
          # What the block is given to report progress through.
          class Handle
            # @param total [Integer]
            # @param bar [TTY::ProgressBar, nil]
            def initialize(total, bar)
              @total = total
              @bar = bar
              @current = 0
            end

            # @return [Integer] the number of units the operation has
            attr_reader :total

            # @return [Integer] the number of units completed so far
            attr_reader :current

            # Marks units as complete. Progress never passes {#total}.
            #
            # @param step [Integer]
            # @return [self]
            def advance(step = 1)
              self.current = (current + step).clamp(0, total)
              bar&.advance(step)
              self
            end

            private

            # @return [TTY::ProgressBar, nil]
            attr_reader :bar

            attr_writer :current
          end

          # Columns kept for the label, percentage, count and ETA around the bar.
          CHROME = 34

          # Narrowest bar drawn.
          MIN_BAR = 10

          # @param terminal [Terminal]
          # @param clock [#call] returns monotonic seconds
          def initialize(terminal, clock:)
            @terminal = terminal
            @clock = clock
          end

          # Runs the block with a progress bar.
          #
          # @param label [String]
          # @param total [Integer] the number of units of work
          # @yieldparam progress [Handle]
          # @return [Object] whatever the block returns
          # @raise [ArgumentError] when total is not a non-negative Integer
          def run(label, total:)
            raise ArgumentError, "total must be a non-negative Integer, got #{total.inspect}" unless total.is_a?(Integer) && total >= 0

            started = clock.call
            bar = start(label, total)
            handle = Handle.new(total, bar)
            ok = false
            result = yield handle
            ok = true
            result
          ensure
            if handle
              bar&.stop
              summary = "#{label} #{handle.current}/#{total}"
              terminal.puts(Outcome.line(terminal, ok ? :done : :failed, summary, clock.call - started))
            end
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @param label [String]
          # @param total [Integer]
          # @return [TTY::ProgressBar, nil]
          def start(label, total)
            unless terminal.animated? && total.positive?
              terminal.puts("#{label}...")
              return
            end

            TTY::ProgressBar.new(
              "#{label} :bar :percent  :current/:total  ETA :eta",
              total: total,
              width: [terminal.width - label.length - CHROME, MIN_BAR].max,
              output: terminal.io,
              complete: "█",
              incomplete: "░",
              clear: true,
              hide_cursor: true
            )
          end
        end
      end
    end
  end
end
