# frozen_string_literal: true

require "concurrent"

module Dry
  class CLI
    module UI
      module Widgets
        # A progress bar with a turning spinner, a percentage, a count and an
        # ETA, followed by the outcome line once the block ends.
        #
        # Each unit can be counted as a success, as auxiliary, or as a failure
        # (see {Handle#advance}). The bar's finished part is drawn left to
        # right in {Configuration#bar_failed_color}, {Configuration#bar_aux_color}
        # and the bar's own colour, each part as wide as its share, and the
        # outcome line ends with the breakdown: `✓ Placing 100/100 (2.1s)  20 failed, 5 auxiliary`.
        #
        # Without an animated terminal it prints `Label...` before the block
        # and the outcome line, with the final count, after it.
        class Progress
          # What the block is given to report progress through.
          class Handle
            # What {#advance} can count a unit as: a success, something
            # relevant but auxiliary, or a failure.
            OUTCOMES = %i[ok aux failed].freeze

            # @param total [Integer, nil] nil until the work finds out
            # @param on_change [#call, nil] called with no arguments whenever
            #   the count or the total changes, by the widget that draws the bar
            # @param color [Symbol, nil] see {Progress.color}
            def initialize(total, on_change = nil, color: nil)
              @total = total
              @on_change = on_change
              @color = color
              @current = 0
              @tally = OUTCOMES.to_h { [it, 0] }
            end

            # @return [Integer, nil] the number of units the operation has; nil
            #   while it is not known
            attr_reader :total

            # @return [Symbol, nil] the Pastel style of the bar's finished part;
            #   nil for {Configuration#bar_color}
            attr_reader :color

            # @return [Integer] the number of units completed so far
            attr_reader :current

            # @return [Hash{Symbol => Integer}] the units completed so far by
            #   outcome, `{ ok:, aux:, failed: }`, adding up to {#current}; frozen
            def counts = @tally.dup.freeze

            # Sets the number of units once the work finds out, such as a download
            # learning its size. {#current} is lowered to fit, taking the units
            # off {#counts} from `:ok` first.
            #
            # @param value [Integer]
            # @raise [ArgumentError] when value is not a non-negative Integer
            def total=(value)
              @total = Progress.total(value)
              settle(current.clamp(0, value), :ok)
              changed
            end

            # Marks units as complete, each counted as the outcome given.
            # Progress never passes {#total} once it is known.
            #
            # @example
            #   bar.advance                  # one unit that succeeded
            #   bar.advance(as: :failed)     # one that failed
            #   bar.advance(3, as: :aux)     # three relevant but auxiliary ones
            #
            # @param step [Integer]
            # @param as [Symbol] one of {OUTCOMES}
            # @return [self]
            # @raise [ArgumentError] when as is not one of {OUTCOMES}
            def advance(step = 1, as: :ok)
              Progress.outcome(as)
              settle((current + step).clamp(0, total), as)
              changed
              self
            end

            # Ends the work as a failure when the block returns, without
            # raising: for work that went on after some of its units failed.
            #
            # @param reason [#to_s, nil] said after the count, such as "2 failed"
            # @return [self]
            def fail(reason = nil)
              @failed = true
              @reason = reason&.to_s
              self
            end

            # @return [Boolean] whether {#fail} was called
            def failed? = @failed == true

            # @return [String, nil] what {#fail} was given
            attr_reader :reason

            # Called by the widget when the block returns. A total that is known
            # and zero ends the work as a failure, with {Progress::NOTHING} as
            # the reason, unless {#fail} was already called.
            #
            # @return [self]
            def finish
              fail(NOTHING) if total&.zero? && !failed?

              self
            end

            # The label and the count, with the failure's reason after it when
            # there is one: `Extracting 1002/1002: 2 failed`.
            #
            # @param label [String]
            # @return [String]
            def summary(label)
              count = "#{label} #{current}/#{total || '?'}"
              failed? && !reason.to_s.empty? ? "#{count}: #{reason}" : count
            end

            private

            # Moves {#current} to a new value, adding the units gained to an
            # outcome, or taking the units lost off that outcome first.
            #
            # @param value [Integer]
            # @param outcome [Symbol]
            # @return [void]
            def settle(value, outcome)
              change = value - current
              @current = value
              return @tally[outcome] += change unless change.negative?

              [outcome, *(OUTCOMES - [outcome])].reduce(-change) do |left, key|
                taken = [left, @tally[key]].min
                @tally[key] -= taken
                left - taken
              end
            end

            # @return [void]
            def changed = @on_change&.call
          end

          # The reason a bar fails with when it ends with nothing to do.
          NOTHING = "nothing to process"

          # Columns kept for the spinner, brackets, percentage, count and ETA around the bar.
          CHROME = 36

          # Narrowest bar drawn.
          MIN_BAR = 10

          # The words the outcome line's breakdown counts with, and the setting
          # each one is painted with.
          BREAKDOWN = { failed: ["failed", :bar_failed_color], aux: ["auxiliary", :bar_aux_color] }.freeze

          # Checks a bar's total.
          #
          # @param value [Integer]
          # @return [Integer] the value
          # @raise [ArgumentError] for anything but a non-negative Integer
          def self.total(value)
            return value if value.is_a?(Integer) && value >= 0

            raise ArgumentError, "total must be a non-negative Integer, got #{value.inspect}"
          end

          # Checks a bar's own colour.
          #
          # @param value [Symbol, nil] any Pastel style, or nil for {Configuration#bar_color}
          # @return [Symbol, nil] the value
          # @raise [ArgumentError] for anything else
          def self.color(value)
            return value if value.nil? || Configuration::STYLES.include?(value)

            raise ArgumentError, "color must be a Pastel style or nil, got #{value.inspect}"
          end

          # Checks what a unit is counted as.
          #
          # @param value [Symbol] one of {Handle::OUTCOMES}
          # @return [Symbol] the value
          # @raise [ArgumentError] for anything else
          def self.outcome(value)
            return value if Handle::OUTCOMES.include?(value)

            raise ArgumentError, "as must be one of #{Handle::OUTCOMES.inspect}, got #{value.inspect}"
          end

          # A bar between brackets, painted as the configuration says: the
          # finished part in {Configuration#bar_color}, or in the bar's own
          # colour when it has one, and all of it on {Configuration#bar_background}.
          #
          # Given counts, the finished part starts with the failed units in
          # {Configuration#bar_failed_color}, then the auxiliary ones in
          # {Configuration#bar_aux_color}, each as wide as its share (see {.segments}).
          #
          # @param pastel [Pastel::Delegator] a no-op when colour is off
          # @param config [Configuration]
          # @param ratio [Float] how much is finished, from 0 to 1
          # @param columns [Integer] the bar's width inside the brackets
          # @param color [Symbol, nil] the finished part's style; nil for {Configuration#bar_color}
          # @param counts [Hash{Symbol => Integer}, nil] units by outcome, as {Handle#counts}
          # @return [String]
          def self.bar(pastel, config, ratio, columns, color: nil, counts: nil)
            filled = (ratio * columns).floor
            failed, aux, ok = counts ? segments(filled, counts) : [0, 0, filled]
            [
              "[",
              paint(pastel, config, config.bar_failed_color) * failed,
              paint(pastel, config, config.bar_aux_color) * aux,
              complete(pastel, config, color) * ok,
              incomplete(pastel, config) * (columns - filled),
              "]"
            ].join
          end

          # Splits a bar's finished cells between the failed, auxiliary and
          # successful units, in proportion to their counts. The cells always
          # add up to the finished width, and each outcome that has units gets
          # at least one cell while the width allows.
          #
          # @param filled [Integer] the finished cells
          # @param counts [Hash{Symbol => Integer}] units by outcome, as {Handle#counts}
          # @return [Array(Integer, Integer, Integer)] failed, auxiliary and successful cells
          def self.segments(filled, counts)
            values = counts.values_at(:failed, :aux, :ok)
            sum = values.sum
            return [0, 0, filled] if sum.zero?

            shares = values.map { it * filled / sum.to_f }
            cells = shares.map(&:floor)
            shares.each_index.sort_by { |index| [cells[index] - shares[index], index] }
                  .first(filled - cells.sum).each { cells[it] += 1 }
            values.each_index do |index|
              next unless values[index].positive? && cells[index].zero?

              donor = cells.index(cells.max)
              next unless cells[donor] > 1

              cells[donor] -= 1
              cells[index] += 1
            end
            cells
          end

          # `[◼◼◼   ]  48%  96/200  ETA 3.1s`. A bar whose total is not known
          # yet is drawn empty, counting `12/?`; an empty one is drawn full.
          #
          # @param pastel [Pastel::Delegator]
          # @param config [Configuration]
          # @param done [Integer]
          # @param all [Integer, nil]
          # @param columns [Integer] the bar's width inside the brackets
          # @param eta [String] the time left, as {.eta} says it
          # @param color [Symbol, nil] the bar's own colour, if any
          # @param counts [Hash{Symbol => Integer}, nil] units by outcome
          # @param count_width [Integer] the columns the count is right-aligned to
          # @return [String]
          def self.meter(pastel, config, done:, all:, columns:, eta:, color: nil, counts: nil, count_width: 0)
            ratio = if all.nil? then 0.0
                    elsif all.zero? then 1.0
                    else done.fdiv(all)
                    end
            format("%<bar>s %<percent>3d%%  %<count>s  ETA %<eta>s",
                   bar: bar(pastel, config, ratio, columns, color: color, counts: counts),
                   percent: (ratio * 100).floor, count: "#{done}/#{all || '?'}".rjust(count_width), eta: eta)
          end

          # The time left at the rate so far.
          #
          # @param done [Integer]
          # @param all [Integer, nil]
          # @yieldreturn [Numeric] the seconds spent so far; asked only when needed
          # @return [String] `--` before any progress or while the total is not known
          def self.eta(done, all)
            return "--" if done.zero? || all.nil?

            Duration.format(yield / done * (all - done))
          end

          # The failed and auxiliary counts, each in its configured colour:
          # `20 failed, 5 auxiliary`.
          #
          # @param pastel [Pastel::Delegator]
          # @param config [Configuration]
          # @param counts [Hash{Symbol => Integer}] units by outcome, as {Handle#counts}
          # @return [String, nil] nil when no unit failed or was auxiliary
          def self.breakdown(pastel, config, counts)
            parts = BREAKDOWN.filter_map do |key, (word, setting)|
              pastel.decorate("#{counts[key]} #{word}", *[config.public_send(setting)].compact) if counts[key].positive?
            end
            parts.join(", ") unless parts.empty?
          end

          # @param pastel [Pastel::Delegator]
          # @param config [Configuration]
          # @param color [Symbol, nil] the style; nil for {Configuration#bar_color}
          # @return [String] one finished cell, painted
          def self.complete(pastel, config, color = nil)
            paint(pastel, config, color || config.bar_color)
          end

          # @param pastel [Pastel::Delegator]
          # @param config [Configuration]
          # @param style [Symbol, nil] the cell's style; nil for none
          # @return [String] one finished cell in the style, on {Configuration#bar_background}
          def self.paint(pastel, config, style)
            pastel.decorate(config.bar_complete, *[style, config.bar_background].compact)
          end

          # @param pastel [Pastel::Delegator]
          # @param config [Configuration]
          # @return [String] one unfinished cell, painted
          def self.incomplete(pastel, config)
            pastel.decorate(config.bar_incomplete, *[config.bar_background].compact)
          end

          # @param terminal [Terminal]
          # @param clock [#call] returns monotonic seconds
          # @param config [Configuration] where the bar's characters come from
          def initialize(terminal, clock:, config: UI.config)
            @terminal = terminal
            @clock = clock
            @config = config
            @lock = Mutex.new
            @live = false
            @frame = 0
          end

          # Runs the block with a progress bar.
          #
          # @param label [String]
          # @param total [Integer] the number of units of work
          # @param color [Symbol, nil] the finished part's Pastel style; nil for
          #   {Configuration#bar_color}
          # @yieldparam progress [Handle]
          # @return [Object] whatever the block returns
          # @raise [ArgumentError] when total is not a non-negative Integer, or
          #   color is not a Pastel style
          def run(label, total:, color: nil)
            Progress.total(total)
            Progress.color(color)
            @label = label
            @started = clock.call
            handle = @handle = Handle.new(total, method(:refresh), color: color)
            terminal.started(handle, label, progress: handle)
            ticker = start
            ok = false
            result = yield handle
            ok = !handle.finish.failed?
            result
          ensure
            if handle
              stop(ticker)
              terminal.finished(handle, ok)
              note = Progress.breakdown(terminal.pastel, config, handle.counts)
              terminal.puts(Outcome.line(terminal, ok ? :done : :failed, handle.summary(label), clock.call - started, note: note))
            end
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @return [Configuration]
          attr_reader :config

          # @return [Mutex] held while the bar is drawn
          attr_reader :lock

          # @return [String]
          attr_reader :label

          # @return [Handle]
          attr_reader :handle

          # @return [Float] when the block started, by the clock
          attr_reader :started

          # Draws the bar and starts its spinner turning when live, or prints
          # the label otherwise.
          #
          # @return [Concurrent::TimerTask, nil]
          def start
            unless terminal.animated? && handle.total.positive?
              terminal.puts("#{label}...")
              return
            end

            terminal.print(terminal.cursor.hide)
            @live = true
            refresh
            Concurrent::TimerTask.new(execution_interval: config.spinner_frame_seconds) { refresh(1) }.tap(&:execute)
          end

          # Stops the spinner and clears the bar.
          #
          # @param ticker [Concurrent::TimerTask, nil]
          # @return [void]
          def stop(ticker)
            ticker&.shutdown
            ticker&.wait_for_termination(1)
            lock.synchronize do
              next unless @live

              @live = false
              terminal.print("#{terminal.cursor.clear_line}#{terminal.cursor.show}")
            end
          end

          # Draws the bar over itself, turning the spinner by some frames.
          #
          # @param turn [Integer] frames to move the spinner on
          # @return [void]
          def refresh(turn = 0)
            lock.synchronize do
              next unless @live

              @frame += turn
              terminal.print("#{terminal.cursor.clear_line}#{row}")
            end
          end

          # `⠋ Importing [◼◼◼   ]  48%  96/200  ETA 3.1s`
          #
          # @return [String]
          def row
            frames = config.spinner_frames
            done = handle.current
            all = handle.total
            meter = Progress.meter(terminal.pastel, config, done: done, all: all, color: handle.color, counts: handle.counts,
                                                            columns: [terminal.width - label.length - CHROME, MIN_BAR].max,
                                                            eta: Progress.eta(done, all) { clock.call - started })
            "#{frames[@frame % frames.size]} #{label} #{meter}"
          end
        end
      end
    end
  end
end
