# frozen_string_literal: true

module Dry
  class CLI
    module UI
      module Widgets
        # The line that says what each colour of a progress bar means:
        #
        #   Color Mapping: [ red: errors and invalid files | yellow: relevant but auxiliary | green: forms ]
        #
        # With colour, each label is drawn on its colour's background instead
        # of naming it. The colours are the configured ones:
        # {Configuration#bar_failed_color}, {Configuration#bar_aux_color} and
        # {Configuration#bar_color}.
        module Legend
          # Each label's keyword, and the setting its colour comes from, in
          # the order a bar draws them.
          SETTINGS = { failed: :bar_failed_color, aux: :bar_aux_color, ok: :bar_color }.freeze

          # @param terminal [Terminal]
          # @param config [Configuration]
          # @param labels [Hash{Symbol => #to_s, nil}] keyed as {SETTINGS};
          #   a nil label is left out
          # @return [String] the line, without a newline
          # @raise [ArgumentError] when every label is nil
          def self.line(terminal, config, labels)
            entries = SETTINGS.filter_map { |key, setting| [labels[key].to_s, config.public_send(setting)] unless labels[key].nil? }
            raise ArgumentError, "legend needs at least one of #{SETTINGS.keys.map { "#{it}:" }.join(', ')}" if entries.empty?

            shown = entries.map { |label, style| terminal.color? ? swatch(terminal.pastel, label, style) : "#{style || 'plain'}: #{label}" }
            "Color Mapping: [ #{shown.join(' | ')} ]"
          end

          # @param pastel [Pastel::Delegator]
          # @param label [String]
          # @param style [Symbol, nil]
          # @return [String] the label, padded, in black on the style's
          #   background; on the style itself when it has no background form
          def self.swatch(pastel, label, style)
            background = :"on_#{style}"
            styles = Configuration::STYLES.include?(background) ? [:black, background] : [style].compact
            pastel.decorate(" #{label} ", *styles)
          end
        end
      end
    end
  end
end
