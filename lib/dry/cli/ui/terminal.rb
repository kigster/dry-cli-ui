# frozen_string_literal: true

require "pastel"
require "tty-cursor"
require "tty-screen"

module Dry
  class CLI
    module UI
      # One output stream, and what it can do.
      #
      # A stream that is not a TTY, or runs under `TERM=dumb`, gets no
      # animation and no cursor movement. `NO_COLOR` (https://no-color.org)
      # additionally switches colour off. Widgets ask these questions rather
      # than inspecting the IO themselves, which is what keeps the fallback in
      # one place.
      class Terminal
        # Width assumed for a stream that is not a TTY.
        DEFAULT_WIDTH = 80

        # Height assumed for a stream that is not a TTY.
        DEFAULT_HEIGHT = 24

        # @param io [IO] the stream to write to
        # @param env [Hash{String => String}] the environment to read NO_COLOR and TERM from
        # @param color [Boolean, nil] force colour on or off; nil decides from the stream
        # @param animate [Boolean, nil] force animation on or off; nil decides from the stream
        # @param width [Integer, nil] force the width; nil asks the terminal
        def initialize(io, env: ENV, color: nil, animate: nil, width: nil)
          @io = io
          @env = env
          @color = color
          @animate = animate
          @width = width
        end

        # @return [IO] the stream this terminal writes to
        attr_reader :io

        # Whether the stream is an interactive terminal.
        #
        # @return [Boolean]
        def tty?
          io.respond_to?(:tty?) && io.tty?
        end

        # Whether spinners may animate and the cursor may move.
        #
        # @return [Boolean]
        def animated?
          return animate unless animate.nil?

          tty? && env["TERM"] != "dumb"
        end

        # Whether to emit ANSI colour codes.
        #
        # @return [Boolean]
        def color?
          return color unless color.nil?

          animated? && env["NO_COLOR"].to_s.empty?
        end

        # @return [Integer] columns available
        def width
          @width || (tty? ? TTY::Screen.width : DEFAULT_WIDTH)
        end

        # @return [Integer] rows available
        def height
          tty? ? TTY::Screen.height : DEFAULT_HEIGHT
        end

        # @return [Pastel::Delegator] a colouriser that is a no-op when colour is off
        def pastel
          @pastel ||= Pastel.new(enabled: color?)
        end

        # @return [Module] TTY::Cursor, for widgets that redraw in place
        def cursor = TTY::Cursor

        # Writes a string without a newline. Flushes, so that output on `out`
        # and `err` stays in the order it was written even when piped.
        #
        # @param text [String]
        # @return [void]
        def print(text)
          io.print(text)
          io.flush if io.respond_to?(:flush)
        end

        # Writes a line, flushing as {#print} does.
        #
        # @param text [String]
        # @return [void]
        def puts(text = "")
          print("#{text}\n")
        end

        private

        # @return [Hash{String => String}]
        attr_reader :env

        # @return [Boolean, nil]
        attr_reader :color

        # @return [Boolean, nil]
        attr_reader :animate
      end
    end
  end
end
