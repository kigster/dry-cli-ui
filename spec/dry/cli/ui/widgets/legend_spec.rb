# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::Legend do
  subject(:line) { described_class.line(terminal, config, labels) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(StringIO.new, env: {}, color: color) }
  let(:config) { Dry::CLI::UI::Configuration.new }
  let(:color) { false }
  let(:labels) { { failed: "errors and invalid files", aux: "relevant but auxiliary", ok: "forms" } }

  context "without colour" do
    it { is_expected.to eq("Color Mapping: [ red: errors and invalid files | yellow: relevant but auxiliary | green: forms ]") }

    context "with colours of its own" do
      before do
        config.bar_failed_color = :magenta
        config.bar_color = nil
      end

      it { is_expected.to eq("Color Mapping: [ magenta: errors and invalid files | yellow: relevant but auxiliary | plain: forms ]") }
    end

    context "with labels left out" do
      let(:labels) { { failed: "errors", aux: nil, ok: "forms" } }

      it { is_expected.to eq("Color Mapping: [ red: errors | green: forms ]") }
    end

    context "without any label" do
      let(:labels) { { failed: nil, aux: nil, ok: nil } }

      it { expect { line }.to raise_error(ArgumentError, "legend needs at least one of failed:, aux:, ok:") }
    end
  end

  context "with colour" do
    let(:color) { true }

    it "draws each label in black on its colour's background" do
      expect(line).to eq("Color Mapping: [ \e[30;41m errors and invalid files \e[0m | \e[30;43m relevant but auxiliary \e[0m | \e[30;42m forms \e[0m ]")
    end

    context "with a colour that has no background form, and one not set" do
      before do
        config.bar_failed_color = :bold
        config.bar_color = nil
      end

      it { is_expected.to eq("Color Mapping: [ \e[1m errors and invalid files \e[0m | \e[30;43m relevant but auxiliary \e[0m |  forms  ]") }
    end
  end
end
