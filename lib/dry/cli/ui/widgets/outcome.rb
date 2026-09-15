# frozen_string_literal: true

module Dry
  class CLI
    module UI
      module Widgets
        # The line an operation leaves behind when it ends: `✓ Loading (1.2s)`.
        # Spinners and progress bars share it, so every operation finishes the
        # same way whether or not the terminal could animate it.
        module Outcome
          # @param terminal [Terminal]
          # @param state [Symbol] `:done` or `:failed`
          # @param label [String] what the operation was
          # @param seconds [Numeric] how long it took
          # @return [String] the line, without a newline
          def self.line(terminal, state, label, seconds)
            glyph, color = Theme::STATES.fetch(state)
            pastel = terminal.pastel
            "#{pastel.decorate(glyph, *color)} #{label} #{pastel.bright_black("(#{Duration.format(seconds)})")}"
          end
        end
      end
    end
  end
end
