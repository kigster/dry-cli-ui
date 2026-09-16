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
            # @param total [Integer, nil] nil until the work finds out
            # @param bar [TTY::ProgressBar, nil]
            # @param color [Symbol, nil] see {Progress.color}
            def initialize(total, bar, color: nil)
              @total = total
              @bar = bar
              @color = color
              @current = 0
            end

            # @return [Integer, nil] the number of units the operation has; nil
            #   while it is not known
            attr_reader :total

            # @return [Symbol, nil] the Pastel style of the bar's finished part;
            #   nil for {Configuration#bar_color}
            attr_reader :color

            # @return [Integer] the number of units completed so far
            attr_reader :current

            # Sets the number of units once the work finds out, such as a download
            # learning its size. {#current} is lowered to fit.
            #
            # @param value [Integer]
            # @raise [ArgumentError] when value is not a non-negative Integer
            def total=(value)
              @total = Progress.total(value)
              self.current = current.clamp(0, value)
              bar&.update(total: value)
            end

            # Marks units as complete. Progress never passes {#total} once it is known.
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

          # Columns kept for the brackets, percentage, count and ETA around the bar.
          CHROME = 36

          # Narrowest bar drawn.
          MIN_BAR = 10

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

          # A bar between brackets, painted as the configuration says: the
          # finished part in {Configuration#bar_color}, or in the bar's own
          # colour when it has one, and all of it on {Configuration#bar_background}.
          #
          # @param pastel [Pastel::Delegator] a no-op when colour is off
          # @param config [Configuration]
          # @param ratio [Float] how much is finished, from 0 to 1
          # @param columns [Integer] the bar's width inside the brackets
          # @param color [Symbol, nil] the finished part's style; nil for {Configuration#bar_color}
          # @return [String]
          def self.bar(pastel, config, ratio, columns, color: nil)
            filled = (ratio * columns).floor
            "[#{complete(pastel, config, color) * filled}#{incomplete(pastel, config) * (columns - filled)}]"
          end

          # @param pastel [Pastel::Delegator]
          # @param config [Configuration]
          # @param color [Symbol, nil] the style; nil for {Configuration#bar_color}
          # @return [String] one finished cell, painted
          def self.complete(pastel, config, color = nil)
            pastel.decorate(config.bar_complete, *[color || config.bar_color, config.bar_background].compact)
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
            started = clock.call
            bar = start(label, total, color)
            handle = Handle.new(total, bar, color: color)
            terminal.started(handle, label, progress: handle)
            ok = false
            result = yield handle
            ok = true
            result
          ensure
            if handle
              bar&.stop
              terminal.finished(handle, ok)
              summary = "#{label} #{handle.current}/#{handle.total}"
              terminal.puts(Outcome.line(terminal, ok ? :done : :failed, summary, clock.call - started))
            end
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @return [Configuration]
          attr_reader :config

          # @param label [String]
          # @param total [Integer]
          # @param color [Symbol, nil]
          # @return [TTY::ProgressBar, nil]
          def start(label, total, color)
            unless terminal.animated? && total.positive?
              terminal.puts("#{label}...")
              return
            end

            TTY::ProgressBar.new(
              "#{label} [:bar] :percent  :current/:total  ETA :eta",
              total: total,
              width: [terminal.width - label.length - CHROME, MIN_BAR].max,
              output: terminal.io,
              complete: Progress.complete(terminal.pastel, config, color),
              incomplete: Progress.incomplete(terminal.pastel, config),
              clear: true,
              hide_cursor: true
            )
          end
        end
      end
    end
  end
end
