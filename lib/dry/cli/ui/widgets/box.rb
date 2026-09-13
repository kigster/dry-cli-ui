# frozen_string_literal: true

require "strings"
require "tty-box"

module Dry
  class CLI
    module UI
      module Widgets
        # A framed panel with a single white border and an optional coloured
        # title.
        #
        # The box is as wide as it is told to be: a fixed number of columns,
        # or the whole terminal less {MARGIN}. It never grows wider than the
        # terminal.
        class Box
          # Columns left free on the right when the box fills the terminal.
          MARGIN = 2

          # Narrowest box drawn, however small the terminal.
          MIN_WIDTH = 20

          # Blank rows above and below the text, and columns either side of it.
          PADDING = [1, 2].freeze

          # @param terminal [Terminal]
          # @param width [Integer, nil] columns; nil fills the terminal
          def initialize(terminal, width: nil)
            @terminal = terminal
            @width = width
          end

          # Renders a box. Each paragraph is wrapped on its own and separated
          # from the next by a blank line.
          #
          # @param paragraphs [Array<#to_s>]
          # @param title [String, nil]
          # @param color [Symbol, nil] Pastel colour for the title
          # @return [String] the box, ending in a newline
          def render(paragraphs, title: nil, color: nil)
            TTY::Box.frame(
              wrap(paragraphs),
              width: box_width,
              padding: PADDING,
              border: :light,
              title: title ? { top_left: heading(title, color) } : {},
              style: { border: { fg: :white } },
              enable_color: terminal.color?
            )
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [Integer, nil]
          attr_reader :width

          # TTY::Box wraps text itself but sizes the box from the unwrapped
          # lines, which silently drops everything past the first few rows.
          # Wrapping here first means its own wrap has nothing left to do.
          #
          # @param paragraphs [Array<#to_s>]
          # @return [String]
          def wrap(paragraphs)
            text_width = box_width - 2 - (PADDING[1] * 2)
            paragraphs.map { |p| Strings::Wrap.wrap(p.to_s, text_width).gsub(/[ \t]+$/, "") }.join("\n\n")
          end

          # @return [Integer]
          def box_width
            available = terminal.width - MARGIN
            [width ? [width, available].min : available, MIN_WIDTH].max
          end

          # @param title [String]
          # @param color [Symbol, nil]
          # @return [String]
          def heading(title, color)
            pastel = terminal.pastel
            styled = color ? pastel.decorate(title, color, :bold) : pastel.bold(title)
            "─ #{styled} "
          end
        end
      end
    end
  end
end
