# frozen_string_literal: true

require "pastel"
require "tty/spinner/formats"
require "tty/progressbar/formats"

module Dry
  class CLI
    module UI
      # Process-wide settings, made once through {UI.configure}:
      #
      #   Dry::CLI::UI.configure do
      #     spinner_format :dots                          # any TTY::Spinner format name
      #     bar_format :box                               # any TTY::ProgressBar bar format name
      #     bar_color :cyan                               # any Pastel style, or nil
      #     bar_background nil                            # any Pastel style, or nil
      #   end
      #
      #   Dry::CLI::UI.configure do |config|
      #     config.spinner_format = { interval: 8, frames: %w[◐ ◓ ◑ ◒] }
      #     config.bar_format = { complete: "#", incomplete: "." }
      #   end
      #
      # Anything not set reads from {DEFAULTS}.
      class Configuration
        # What a setting reads before it is set: a green `◼` for each finished
        # part of a bar, over a gray track the whole bar's width.
        DEFAULTS = {
          spinner_format: :dots,
          bar_format: { complete: "◼", incomplete: " " }.freeze,
          bar_color: :green,
          bar_background: :on_bright_black
        }.freeze

        # Every style name Pastel knows, for checking colour settings.
        STYLES = Pastel.new(enabled: true).styles.keys.freeze

        # Marks a DSL call made without a value, which reads instead of writes.
        UNSET = Object.new.freeze
        private_constant :UNSET

        def initialize
          @values = {}
        end

        # @!method spinner_format(value = UNSET)
        #   Reads the spinner format, or sets it when given a value.
        #   @param value [Symbol, Hash] a key of `TTY::Formats::FORMATS`, or
        #     `{ interval:, frames: }`: frames per second, and the frames
        #   @return [Symbol, Hash]
        # @!method bar_format(value = UNSET)
        #   Reads the bar format, or sets it when given a value.
        #   @param value [Symbol, Hash] a key of `TTY::ProgressBar::Formats::FORMATS`,
        #     or `{ complete:, incomplete: }`
        #   @return [Symbol, Hash]
        # @!method bar_color(value = UNSET)
        #   Reads the colour a bar's finished part is drawn in, or sets it.
        #   @param value [Symbol, nil] a Pastel style, such as :green; nil for none
        #   @return [Symbol, nil]
        # @!method bar_background(value = UNSET)
        #   Reads the background the whole bar is drawn on, or sets it.
        #   @param value [Symbol, nil] a Pastel style, such as :on_bright_black; nil for none
        #   @return [Symbol, nil]
        DEFAULTS.each_key do |name|
          define_method(name) do |value = UNSET|
            return @values.fetch(name) { DEFAULTS.fetch(name) } if UNSET.equal?(value)

            public_send(:"#{name}=", value)
          end
        end

        # @param value [Symbol, Hash] see {#spinner_format}
        # @raise [ArgumentError] for an unknown name or a malformed Hash
        def spinner_format=(value)
          @values[:spinner_format] = spinner_definition(value) && value
        end

        # @param value [Symbol, Hash] see {#bar_format}
        # @raise [ArgumentError] for an unknown name or a malformed Hash
        def bar_format=(value)
          @values[:bar_format] = bar_definition(value) && value
        end

        # @param value [Symbol, nil] see {#bar_color}
        # @raise [ArgumentError] for a style Pastel does not know
        def bar_color=(value)
          @values[:bar_color] = style(:bar_color, value)
        end

        # @param value [Symbol, nil] see {#bar_background}
        # @raise [ArgumentError] for a style Pastel does not know
        def bar_background=(value)
          @values[:bar_background] = style(:bar_background, value)
        end

        # @return [Array<String>] the frames a spinner cycles through
        def spinner_frames
          frames = spinner_definition(spinner_format).fetch(:frames)
          frames.is_a?(String) ? frames.chars : frames
        end

        # @return [Float] seconds between two spinner frames
        def spinner_frame_seconds
          1.0 / spinner_definition(spinner_format).fetch(:interval)
        end

        # @return [String] what a finished part of a bar is drawn with
        def bar_complete
          bar_definition(bar_format).fetch(:complete)
        end

        # @return [String] what an unfinished part of a bar is drawn with
        def bar_incomplete
          bar_definition(bar_format).fetch(:incomplete)
        end

        private

        # @param value [Symbol, Hash]
        # @return [Hash{Symbol => Object}] with :interval and :frames
        def spinner_definition(value)
          return TTY::Formats::FORMATS.fetch(value) { unknown(:spinner_format, value) } if value.is_a?(Symbol)

          valid = value.is_a?(Hash) && value[:interval].is_a?(Numeric) && value[:interval].positive? &&
                  (value[:frames].is_a?(String) || value[:frames].is_a?(Array)) && !value[:frames].empty?
          valid ? value : malformed(:spinner_format, value, "{ interval: Numeric, frames: Array }")
        end

        # @param value [Symbol, Hash]
        # @return [Hash{Symbol => String}] with :complete and :incomplete
        def bar_definition(value)
          return TTY::ProgressBar::Formats::FORMATS.fetch(value) { unknown(:bar_format, value) } if value.is_a?(Symbol)

          valid = value.is_a?(Hash) && value[:complete].is_a?(String) && value[:incomplete].is_a?(String)
          valid ? value : malformed(:bar_format, value, "{ complete: String, incomplete: String }")
        end

        # @param setting [Symbol]
        # @param value [Symbol, nil]
        # @return [Symbol, nil] the value
        # @raise [ArgumentError] for anything but nil or a style Pastel knows
        def style(setting, value)
          return value if value.nil? || STYLES.include?(value)

          raise ArgumentError, "#{setting} must be a Pastel style or nil, got #{value.inspect}"
        end

        # @raise [ArgumentError]
        def unknown(setting, value)
          raise ArgumentError, "#{setting} #{value.inspect} is not a known format"
        end

        # @raise [ArgumentError]
        def malformed(setting, value, shape)
          raise ArgumentError, "#{setting} must be a format name or #{shape}, got #{value.inspect}"
        end
      end
    end
  end
end
