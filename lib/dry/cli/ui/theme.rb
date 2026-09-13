# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # The six message levels and how each one looks.
      module Theme
        # How one message level is presented.
        #
        # @!attribute [r] name
        #   @return [Symbol] the level, e.g. `:error`
        # @!attribute [r] title
        #   @return [String] the box title, e.g. "Error"
        # @!attribute [r] glyph
        #   @return [String] the status-line marker, e.g. "✗"
        # @!attribute [r] color
        #   @return [Symbol] a Pastel colour for the title and glyph
        # @!attribute [r] stream
        #   @return [Symbol] `:out` or `:err`, where messages at this level go
        Level = ::Data.define(:name, :title, :glyph, :color, :stream)

        # Every level, keyed by name. Diagnostics go to STDERR so that a
        # command's real output can still be piped.
        LEVELS = {
          debug: Level.new(name: :debug, title: "Debug", glyph: "·", color: :bright_black, stream: :err),
          info: Level.new(name: :info, title: "Info", glyph: "ℹ", color: :cyan, stream: :out),
          success: Level.new(name: :success, title: "Success", glyph: "✓", color: :green, stream: :out),
          warn: Level.new(name: :warn, title: "Warning", glyph: "⚠", color: :yellow, stream: :err),
          error: Level.new(name: :error, title: "Error", glyph: "✗", color: :red, stream: :err),
          fatal: Level.new(name: :fatal, title: "Fatal", glyph: "✖", color: :magenta, stream: :err)
        }.freeze

        # Glyphs for the states an operation passes through.
        STATES = {
          pending: ["○", :bright_black],
          running: ["▸", :cyan],
          done: ["✓", :green],
          failed: ["✗", :red],
          skipped: ["–", :bright_black]
        }.freeze

        # Looks up a level by name.
        #
        # @param name [Symbol] one of {LEVELS}' keys
        # @return [Level]
        # @raise [ArgumentError] when the level does not exist
        def self.level(name)
          LEVELS.fetch(name) { raise ArgumentError, "unknown level #{name.inspect}, expected one of #{LEVELS.keys}" }
        end
      end
    end
  end
end
