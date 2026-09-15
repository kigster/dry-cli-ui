# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    its(:spinner_format) { is_expected.to eq(:dots) }
    its(:bar_format) { is_expected.to eq(complete: "◼", incomplete: " ") }
    its(:bar_color) { is_expected.to eq(:green) }
    its(:bar_background) { is_expected.to eq(:on_bright_black) }
    its(:spinner_frames) { is_expected.to eq(%w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]) }
    its(:spinner_frame_seconds) { is_expected.to eq(0.1) }
    its(:bar_complete) { is_expected.to eq("◼") }
    its(:bar_incomplete) { is_expected.to eq(" ") }
  end

  describe "#spinner_format" do
    it "takes any TTY::Spinner format name, through the DSL or a writer" do
      config.spinner_format(:classic)
      expect(config.spinner_frames).to eq(%w[| / - \\])

      config.spinner_format = :pong
      expect(config.spinner_format).to eq(:pong)
    end

    it "takes frames and frames per second" do
      config.spinner_format = { interval: 4, frames: %w[◐ ◓ ◑ ◒] }
      expect([config.spinner_frames, config.spinner_frame_seconds]).to eq([%w[◐ ◓ ◑ ◒], 0.25])
    end

    it "splits frames given as one String" do
      config.spinner_format = { interval: 10, frames: "-=" }
      expect(config.spinner_frames).to eq(%w[- =])
    end

    it "rejects an unknown name" do
      expect { config.spinner_format = :sparkly }.to raise_error(ArgumentError, /spinner_format :sparkly/)
    end

    it "rejects a malformed definition" do
      [{ frames: %w[a] }, { interval: 0, frames: %w[a] }, { interval: 1, frames: [] }, "dots"].each do |bad|
        expect { config.spinner_format = bad }.to raise_error(ArgumentError, /interval: Numeric/)
      end
    end
  end

  describe "#bar_color and #bar_background" do
    it "take any Pastel style, through the DSL or a writer" do
      config.bar_color(:cyan)
      config.bar_background = :on_blue
      expect([config.bar_color, config.bar_background]).to eq(%i[cyan on_blue])
    end

    it "take nil for none" do
      config.bar_color = nil
      config.bar_background nil
      expect([config.bar_color, config.bar_background]).to eq([nil, nil])
    end

    it "reject a style Pastel does not know" do
      expect { config.bar_color = :sparkly }.to raise_error(ArgumentError, /bar_color must be a Pastel style/)
      expect { config.bar_background = "gray" }.to raise_error(ArgumentError, /bar_background/)
    end
  end

  describe "#bar_format" do
    it "takes any TTY::ProgressBar bar format name" do
      config.bar_format :classic
      expect([config.bar_complete, config.bar_incomplete]).to eq(["=", " "])
    end

    it "takes the two characters" do
      config.bar_format = { complete: "#", incomplete: "." }
      expect([config.bar_complete, config.bar_incomplete]).to eq(["#", "."])
    end

    it "rejects an unknown name" do
      expect { config.bar_format = :sparkly }.to raise_error(ArgumentError, /bar_format :sparkly/)
    end

    it "rejects a malformed definition" do
      expect { config.bar_format = { complete: "#" } }.to raise_error(ArgumentError, /complete: String/)
    end
  end
end
