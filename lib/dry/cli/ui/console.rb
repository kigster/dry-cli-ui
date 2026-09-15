# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # The object {UI#ui} returns: a small semantic API for what a command
      # wants to say, independent of how the terminal renders it.
      #
      # Messages about the command itself (`debug`, `warn`, `error`, `fatal`),
      # spinners, progress bars, task trees and prompts go to `err`. The
      # command's results (`info`, `success`, tables, plain boxes) go to
      # `out`. Piping a command's output therefore captures its results and
      # nothing else.
      #
      # @example
      #   ui = Dry::CLI::UI::Console.new
      #   ui.info "Importing tax rules..."
      #   rules = ui.spinner("Loading YAML") { load_rules }
      #   ui.progress("Importing", total: rules.size) do |bar|
      #     rules.each do |rule|
      #       import(rule)
      #       bar.advance
      #     end
      #   end
      #   ui.success "Imported #{rules.size} rules"
      class Console
        # @!method debug(*paragraphs, width: nil)
        #   A grey "Debug" box on `err`.
        #   @param paragraphs [Array<#to_s>] each one wrapped on its own, separated by a blank line
        #   @param width [Integer, nil] columns, overriding the console's box width
        #   @return [nil]
        # @!method info(*paragraphs, width: nil)
        #   A cyan "Info" box on `out`.
        #   @param (see #debug)
        #   @return [nil]
        # @!method success(*paragraphs, width: nil)
        #   A green "Success" box on `out`.
        #   @param (see #debug)
        #   @return [nil]
        # @!method warn(*paragraphs, width: nil)
        #   A yellow "Warning" box on `err`.
        #   @param (see #debug)
        #   @return [nil]
        # @!method error(*paragraphs, width: nil)
        #   A red "Error" box on `err`.
        #   @param (see #debug)
        #   @return [nil]
        # @!method fatal(*paragraphs, width: nil)
        #   A magenta "Fatal" box on `err`.
        #   @param (see #debug)
        #   @return [nil]
        Theme::LEVELS.each_key do |level|
          define_method(level) do |*paragraphs, width: nil|
            box(*paragraphs, level: level, width: width)
          end
        end

        # @param out [IO] where results go
        # @param err [IO] where diagnostics, progress and prompts go
        # @param input [IO] where prompt answers come from
        # @param env [Hash{String => String}] read for NO_COLOR and TERM
        # @param color [Boolean, nil] force colour on or off; nil decides per stream
        # @param animate [Boolean, nil] force animation on or off; nil decides per stream
        # @param width [Integer, nil] force the terminal width; nil asks the terminal
        # @param box_width [Integer, nil] box width in columns; nil fills the terminal
        # @param clock [#call] returns monotonic seconds
        def initialize(out: $stdout, err: $stderr, input: $stdin, env: ENV, color: nil, animate: nil,
                       width: nil, box_width: nil, clock: Duration::CLOCK)
          @out = Terminal.new(out, env: env, color: color, animate: animate, width: width)
          @err = Terminal.new(err, env: env, color: color, animate: animate, width: width)
          @input = input
          @box_width = box_width
          @clock = clock
        end

        # A framed panel. Given a level, it takes that level's title, colour
        # and stream; without one it is untitled unless given a title, and goes
        # to `out`.
        #
        # @example
        #   ui.box("Name: Alan Turing", "Role: Cryptanalyst", title: "Profile")
        #
        # @param paragraphs [Array<#to_s>] each one wrapped on its own, separated by a blank line
        # @param title [String, nil] overrides the level's title
        # @param level [Symbol, nil] one of {Theme::LEVELS}
        # @param width [Integer, nil] columns, overriding the console's box width
        # @return [nil]
        def box(*paragraphs, title: nil, level: nil, width: nil)
          theme = level && Theme.level(level)
          terminal = theme ? stream(theme) : out
          widget = Widgets::Box.new(terminal, width: width || box_width)
          terminal.print(widget.render(paragraphs, title: title || theme&.title, color: theme&.color))
          nil
        end

        # A box drawn over whatever is on the screen, on `err`. On an animated
        # terminal it is as wide as its text needs, up to the box width, and
        # centred, and the cursor is left where it was. Otherwise it is the
        # same box {#box} draws.
        #
        # @example
        #   ui.popup("h  help", "q  quit", title: "Keys")
        #
        # @param paragraphs [Array<#to_s>] each one wrapped on its own, separated by a blank line
        # @param title [String, nil]
        # @param width [Integer, nil] the widest it may be, overriding the console's box width
        # @return [nil]
        def popup(*paragraphs, title: nil, width: nil)
          err.print(Widgets::Box.new(err, width: width || box_width).popup(paragraphs, title: title))
          nil
        end

        # One line with a coloured glyph, going to the level's stream.
        #
        # @example
        #   ui.status "Connected to the database", level: :success   # ✓ Connected to the database
        #
        # @param words [Array<#to_s>] joined with spaces
        # @param level [Symbol] one of {Theme::LEVELS}
        # @return [nil]
        def status(*words, level: :info)
          theme = Theme.level(level)
          terminal = stream(theme)
          terminal.puts(Widgets::Status.line(terminal, theme, words.join(" ")))
          nil
        end

        # Runs a block under a spinner and leaves `✓ label (1.2s)` behind, or
        # `✗ label` when the block raises.
        #
        # @param label [String]
        # @yield the work
        # @return [Object] whatever the block returns
        # @raise [ArgumentError] without a block
        def spinner(label, &)
          raise ArgumentError, "spinner needs a block" unless block_given?

          Widgets::Spinner.new(err, clock: clock).run(label, &)
        end

        # Runs a block with a progress bar showing percent, count and ETA.
        #
        # @param label [String]
        # @param total [Integer] units of work
        # @yieldparam progress [Widgets::Progress::Handle] call `advance` as units complete
        # @return [Object] whatever the block returns
        # @raise [ArgumentError] without a block, or when total is not a non-negative Integer
        def progress(label, total:, &)
          raise ArgumentError, "progress needs a block" unless block_given?

          Widgets::Progress.new(err, clock: clock).run(label, total: total, &)
        end

        # Declares a tree of tasks, then runs it, showing each task's state
        # and elapsed time. See {Widgets::Tasks}.
        #
        # @example Several operations at once
        #   ui.tasks("Fetching", concurrent: true) do |t|
        #     t.task("fonts") { fetch(:fonts) }
        #     t.task("images") { fetch(:images) }
        #   end
        #
        # @param title [String, nil]
        # @param concurrent [Boolean] run the top-level tasks at the same time
        # @yieldparam tasks [Widgets::Tasks::Builder] declares `task`s and `group`s
        # @return [nil]
        # @raise [ArgumentError] without a block
        def tasks(title = nil, concurrent: false, &)
          raise ArgumentError, "tasks needs a block" unless block_given?

          Widgets::Tasks.new(err, clock: clock).run(title, concurrent: concurrent, &)
        end

        # Prints a table to `out`.
        #
        # @example
        #   ui.table([["Alan Turing", 41]], header: ["Name", "Age"])
        #
        # @param rows [Array<Array<#to_s>>]
        # @param header [Array<#to_s>, nil]
        # @return [nil]
        def table(rows, header: nil)
          out.print(Widgets::Table.new(out).render(rows, header: header))
          nil
        end

        # Asks a question. See {Widgets::Prompt#ask}.
        #
        # @example
        #   ui.prompt("Environment?", choices: %w[staging production], default: "staging")
        #
        # @param question [String]
        # @param default [Object, nil]
        # @param choices [Array<String>, Hash{String => Object}, nil]
        # @return [Object, nil]
        # @raise [NonInteractiveError] when the input is exhausted and there is no default
        def prompt(question, default: nil, choices: nil)
          prompter.ask(question, default: default, choices: choices)
        end

        # Asks a yes/no question.
        #
        # @param question [String]
        # @param default [Boolean]
        # @return [Boolean]
        def confirm(question, default: false)
          prompter.confirm(question, default: default)
        end

        private

        # @return [Terminal]
        attr_reader :out

        # @return [Terminal]
        attr_reader :err

        # @return [IO]
        attr_reader :input

        # @return [Integer, nil]
        attr_reader :box_width

        # @return [#call]
        attr_reader :clock

        # @param theme [Theme::Level]
        # @return [Terminal]
        def stream(theme)
          theme.stream == :err ? err : out
        end

        # @return [Widgets::Prompt]
        def prompter
          @prompter ||= Widgets::Prompt.new(input: input, terminal: err)
        end
      end
    end
  end
end
