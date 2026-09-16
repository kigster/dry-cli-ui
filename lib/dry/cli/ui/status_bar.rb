# frozen_string_literal: true

require "concurrent"
require "monitor"
require "strings"

module Dry
  class CLI
    module UI
      # A line kept at the bottom of the screen while a block runs, under a
      # rule, saying how the command is doing overall:
      #
      #   ⠋ deploy · Migrating users · 2 running · 5 done · 1 failed · [◼◼◼◼      ] 42% · 12.3s   ^C cancel
      #
      # Every spinner, progress bar, multi widget and task tree started inside
      # the block reports to it, so a command only supplies the title and the
      # hints. Everything else the console writes prints above it, and the
      # scrollback stays intact: no scroll region is set.
      #
      # It works by standing between the console's terminals and their
      # streams. Each write first clears the two rows below the cursor, then
      # writes, then draws them again, and puts the cursor back where the
      # write left it. Writes that bypass the console, such as a bare `puts`,
      # land where the bar is and are drawn over by the next write.
      class StatusBar
        # Rows the bar takes: a rule, then the status line.
        ROWS = 2

        # Columns of the overall progress bar.
        BAR = 10

        # Clears from the cursor to the end of the screen.
        CLEAR_BELOW = "\e[J"

        # The last column a stream's cursor is in, followed through what is
        # written to it, so the cursor can be put back after the bar is drawn.
        class Column
          # One control sequence, a line break, or a run of text.
          TOKEN = /\e\[[\d;?]*[A-Za-z]|\e[78]|\r|\n|[^\e\r\n]+|\e/

          def initialize
            @column = 0
            @saved = 0
          end

          # @return [Integer] zero-based
          attr_reader :column

          # @param text [String] what was just written
          # @return [Integer] the column after it
          def follow(text)
            text.scan(TOKEN) { |token| step(token) }
            column
          end

          private

          # @param token [String]
          # @return [void]
          def step(token)
            case token
            when "\n", "\r" then @column = 0
            when "\e7", "\e[s" then @saved = @column
            when "\e8", "\e[u" then @column = @saved
            when /\A\e\[(\d*)([GCD])\z/ then move(Regexp.last_match(1), Regexp.last_match(2))
            when /\A\e/ then nil
            else @column += Strings::ANSI.sanitize(token).then { |plain| Unicode::DisplayWidth.of(plain) }
            end
          end

          # @param count [String] the sequence's number, empty for its default
          # @param kind [String] G, C or D
          # @return [void]
          def move(count, kind)
            n = count.empty? ? 1 : count.to_i
            @column = case kind
                      when "G" then n - 1
                      when "C" then @column + n
                      else [@column - n, 0].max
                      end
          end
        end

        # Stands in for a terminal's stream while the bar runs.
        class Output
          # @param io [IO] the real stream
          # @param bar [StatusBar]
          def initialize(io, bar)
            @io = io
            @bar = bar
          end

          # @param text [#to_s]
          # @return [Integer] bytes written
          def write(*text)
            text = text.join
            @bar.around_write(@io, text)
            text.bytesize
          end

          # @param text [Array<#to_s>]
          # @return [nil]
          def print(*text)
            write(*text)
            nil
          end

          # @param text [#to_s]
          # @return [self]
          def <<(text)
            write(text)
            self
          end

          # @return [Boolean] always true: a bar is only drawn on a terminal
          def tty? = true

          # @return [void]
          def flush
            @io.flush if @io.respond_to?(:flush)
          end

          # @return [Boolean]
          def respond_to_missing?(name, include_private = false) = @io.respond_to?(name, include_private) || super

          # Anything else the stream answers, such as `winsize`.
          def method_missing(name, ...)
            @io.respond_to?(name) ? @io.public_send(name, ...) : super
          end
        end

        # @param terminal [Terminal] where the bar is drawn
        # @param others [Array<Terminal>] other terminals on the same screen,
        #   whose writes must also go above the bar
        # @param title [String, nil]
        # @param hints [Array<String>] shown at the right, such as "^C cancel"
        # @param clock [#call] returns monotonic seconds
        # @param config [Configuration] where the spinner frames and bar characters come from
        def initialize(terminal, others: [], title: nil, hints: [], clock: Duration::CLOCK, config: UI.config)
          @terminal = terminal
          @terminals = [terminal, *others]
          @title = title
          @hints = hints
          @clock = clock
          @config = config
          @monitor = Monitor.new
          @column = Column.new
          @running = {}
          @finished = []
          @done = 0
          @failed = 0
          @frame = 0
        end

        # Draws the bar, runs the block, and takes the bar away again.
        #
        # @return [Object] whatever the block returns
        def run
          @started = clock.call
          ticker = Concurrent::TimerTask.new(execution_interval: config.spinner_frame_seconds) { tick }
          streams = @terminals.to_h { |terminal| [terminal, terminal.io] }
          streams.each { |terminal, io| terminal.redirect(Output.new(io, self), reporter: self, reserved: ROWS) }
          begin
            terminal.print("")
            ticker.execute
            yield
          ensure
            ticker.shutdown
            ticker.wait_for_termination(1)
            streams.each { |terminal, io| terminal.redirect(io) }
            synchronize { terminal.io.print(CLEAR_BELOW) }
          end
        end

        # Records that work has started. Widgets report through {Terminal#started}.
        #
        # @param key [Object] identifies the work until it finishes
        # @param label [String]
        # @param progress [#current, #total, nil] read whenever the bar is drawn
        # @return [void]
        def started(key, label, progress: nil)
          synchronize { @running[key] = [label, progress] }
        end

        # Records that work has ended. Widgets report through {Terminal#finished}.
        #
        # @param key [Object] as given to {#started}
        # @param succeeded [Boolean]
        # @return [void]
        def finished(key, succeeded)
          synchronize do
            _, progress = @running.delete(key)
            @finished << progress if progress
            succeeded ? @done += 1 : @failed += 1
          end
        end

        # Writes text to a stream above the bar. For {Output}.
        #
        # @param io [IO]
        # @param text [String]
        # @return [void]
        def around_write(io, text)
          synchronize do
            @column.follow(text)
            io.print("#{CLEAR_BELOW}#{text}#{footer}")
          end
        end

        # The status line, as wide as the terminal at most.
        #
        # @return [String]
        def line
          synchronize do
            pastel = terminal.pastel
            fields = [title && pastel.bold(title), current, *counts, meter, Duration.format(clock.call - @started)]
            fit(" #{glyph} #{fields.compact.join(pastel.bright_black(' · '))}", pastel.bright_black(hints.join("  ")))
          end
        end

        private

        # @return [Terminal]
        attr_reader :terminal

        # @return [String, nil]
        attr_reader :title

        # @return [Array<String>]
        attr_reader :hints

        # @return [#call]
        attr_reader :clock

        # @return [Configuration]
        attr_reader :config

        # @return [void]
        def synchronize(&) = @monitor.synchronize(&)

        # @return [void]
        def tick
          synchronize do
            @frame += 1
            terminal.io.print("")
          end
        end

        # The rule and the status line below the cursor, and the sequence that
        # puts the cursor back. From the start of a row, the bar starts on that
        # row; from anywhere else, on the next.
        #
        # @return [String]
        def footer
          rule = terminal.pastel.bright_black("─" * terminal.width)
          rows = "\e[2K#{rule}\n\e[2K#{line}"
          col = @column.column
          return "#{rows}\e[#{ROWS - 1}A\r" if col.zero?

          "\n#{rows}\e[#{ROWS}A\e[#{col + 1}G"
        end

        # @return [String] a turning spinner while anything runs, a dot otherwise
        def glyph
          return terminal.pastel.bright_black("·") if @running.empty?

          frames = config.spinner_frames
          terminal.pastel.cyan(frames[@frame % frames.size])
        end

        # @return [String, nil] the label of the work started most recently
        def current = @running.values.last&.first

        # @return [Array<String>]
        def counts
          pastel = terminal.pastel
          [
            (pastel.cyan("#{@running.size} running") if @running.any?),
            (pastel.green("#{@done} done") if @done.positive?),
            (pastel.red("#{@failed} failed") if @failed.positive?)
          ].compact
        end

        # @return [String, nil] a bar over every progress reported so far
        def meter
          progress = @finished + @running.values.filter_map(&:last)
          total = progress.sum { |item| item.total || item.current }
          return if total.zero?

          ratio = progress.sum(&:current).fdiv(total)
          "#{Widgets::Progress.bar(terminal.pastel, config, ratio, BAR)} #{(ratio * 100).floor}%"
        end

        # The left part, with the hints right-aligned after it when they fit,
        # truncated to the terminal's width.
        #
        # @param left [String]
        # @param right [String]
        # @return [String]
        def fit(left, right)
          width = terminal.width
          gap = width - display(left) - display(right) - 1
          return "#{left}#{' ' * gap}#{right}" if gap >= 2 && !hints.empty?

          Strings::Truncate.truncate(left, width - 1)
        end

        # @param text [String]
        # @return [Integer] columns, not counting escape codes
        def display(text) = Unicode::DisplayWidth.of(Strings::ANSI.sanitize(text))
      end
    end
  end
end
