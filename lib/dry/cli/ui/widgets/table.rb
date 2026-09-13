# frozen_string_literal: true

require "tty-table"

module Dry
  class CLI
    module UI
      module Widgets
        # Rows and an optional bold header, framed with box-drawing lines.
        #
        # Tables are data, so they are never narrowed to fit the terminal: a
        # column is not truncated and a table is not rotated. A table wider
        # than the screen wraps the way any long line does.
        class Table
          # Wider than any table anyone will render. TTY::Table otherwise
          # measures the screen, warns on STDERR, and turns a wide table on
          # its side.
          UNLIMITED = 1_000_000

          # @param terminal [Terminal]
          def initialize(terminal)
            @terminal = terminal
          end

          # @param rows [Array<Array<#to_s>>]
          # @param header [Array<#to_s>, nil]
          # @return [String] the table ending in a newline, or "" when there are no rows
          def render(rows, header: nil)
            return "" if rows.empty?

            table = TTY::Table.new(
              header: header&.map { |cell| terminal.pastel.bold(cell.to_s) },
              rows: rows.map { |row| row.map(&:to_s) }
            )
            "#{table.render(:unicode, padding: [0, 1], width: UNLIMITED)}\n"
          end

          private

          # @return [Terminal]
          attr_reader :terminal
        end
      end
    end
  end
end
