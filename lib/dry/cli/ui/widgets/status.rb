# frozen_string_literal: true

module Dry
  class CLI
    module UI
      module Widgets
        # A single line with a coloured glyph: `✓ Connected to the database`.
        # The light-weight sibling of {Box}.
        module Status
          # @param terminal [Terminal]
          # @param level [Theme::Level]
          # @param text [String]
          # @return [String] the line, without a newline
          def self.line(terminal, level, text)
            "#{terminal.pastel.decorate(level.glyph, level.color)} #{text}"
          end
        end
      end
    end
  end
end
