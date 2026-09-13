# frozen_string_literal: true

require "tty/prompt/test"

RSpec.describe Dry::CLI::UI::Widgets::Prompt do
  subject(:prompt) { described_class.new(input: input, terminal: terminal) }

  let(:output) { StringIO.new }
  let(:terminal) { Dry::CLI::UI::Terminal.new(output, env: {}) }
  let(:input) { StringIO.new(answers) }
  let(:answers) { "" }

  describe "#ask, reading from a pipe" do
    context "with an answer" do
      let(:answers) { "  Alan Turing \n" }

      it { expect(prompt.ask("Name?")).to eq("Alan Turing") }

      it "prints the question and the default" do
        prompt.ask("Name?", default: "Ada")
        expect(output.string).to eq("Name? [Ada] ")
      end
    end

    context "with an empty answer" do
      let(:answers) { "\n" }

      it { expect(prompt.ask("Name?", default: "Ada")).to eq("Ada") }
      it { expect(prompt.ask("Name?")).to be_nil }
    end

    context "with no input left" do
      it { expect(prompt.ask("Name?", default: "Ada")).to eq("Ada") }

      it "refuses to invent an answer" do
        expect { prompt.ask("Name?") }.to raise_error(Dry::CLI::UI::NonInteractiveError, /no answer for "Name\?"/)
      end
    end
  end

  describe "#ask with choices, reading from a pipe" do
    subject(:answer) { prompt.ask("Environment?", choices: choices, default: default) }

    let(:choices) { %w[staging production] }
    let(:default) { nil }

    context "given a number" do
      let(:answers) { "2\n" }

      it { is_expected.to eq("production") }

      it "lists the choices" do
        answer
        expect(output.string).to eq("Environment?\n  1) staging\n  2) production\nChoose 1-2: ")
      end
    end

    context "given a name" do
      let(:answers) { "staging\n" }

      it { is_expected.to eq("staging") }
    end

    context "given names mapped to values" do
      let(:choices) { { "Staging" => :stg, "Production" => :prd } }
      let(:answers) { "Production\n" }

      it { is_expected.to eq(:prd) }
    end

    context "given something else first" do
      let(:answers) { "7\nqa\n\n1\n" }

      before { answer }

      it { is_expected.to eq("staging") }
      it { expect(output.string.scan("Choose a number from 1 to 2").size).to eq(3) }
    end

    context "given an empty answer with a default" do
      let(:answers) { "\n" }
      let(:default) { "production" }

      before { answer }

      it { is_expected.to eq("production") }
      it { expect(output.string).to end_with("Choose 1-2 [production]: ") }
    end

    context "with no input left and a default" do
      let(:default) { "production" }

      it { is_expected.to eq("production") }
    end

    context "with no input left and no default" do
      it { expect { answer }.to raise_error(Dry::CLI::UI::NonInteractiveError, /no valid choice/) }
    end

    context "with no input left and a default that is not a choice" do
      let(:default) { "qa" }

      it { expect { answer }.to raise_error(Dry::CLI::UI::NonInteractiveError) }
    end
  end

  describe "#confirm, reading from a pipe" do
    {
      "y\n" => true, "YES\n" => true, "n\n" => false, "no\n" => false, "maybe\ny\n" => true
    }.each do |typed, expected|
      context "given #{typed.inspect}" do
        let(:answers) { typed }

        it { expect(prompt.confirm("Deploy?")).to be(expected) }
      end
    end

    context "given nothing" do
      let(:answers) { "\n" }

      it { expect(prompt.confirm("Deploy?", default: true)).to be(true) }
      it { expect(prompt.confirm("Deploy?")).to be(false) }
    end

    context "with no input left" do
      it { expect(prompt.confirm("Deploy?", default: true)).to be(true) }
    end

    it "shows which answer is the default" do
      prompt.confirm("Deploy?", default: true)
      prompt.confirm("Deploy?", default: false)
      expect(output.string).to eq("Deploy? (Y/n) Deploy? (y/N) ")
    end

    context "given something unrecognised" do
      let(:answers) { "maybe\n" }

      it "asks again" do
        prompt.confirm("Deploy?")
        expect(output.string).to include("Please answer y or n.")
      end
    end
  end

  describe "on an interactive terminal" do
    subject(:prompt) { described_class.new(input: input, terminal: terminal, backend: backend) }

    let(:input) { FakeTTY.new }
    let(:terminal) { Dry::CLI::UI::Terminal.new(FakeTTY.new, env: {}) }
    let(:backend) { TTY::Prompt::Test.new }

    it "asks through the backend" do
      backend.input << "Alan Turing\n"
      backend.input.rewind
      expect(prompt.ask("Name?")).to eq("Alan Turing")
    end

    it "passes a default through" do
      backend.input << "\n"
      backend.input.rewind
      expect(prompt.ask("Name?", default: "Ada")).to eq("Ada")
    end

    it "selects with the arrow keys" do
      backend.input << "\e[B\r"
      backend.input.rewind
      expect(prompt.ask("Environment?", choices: %w[staging production])).to eq("production")
    end

    it "confirms" do
      backend.input << "y\n"
      backend.input.rewind
      expect(prompt.confirm("Deploy?")).to be(true)
    end

    context "without a backend" do
      subject(:prompt) { described_class.new(input: input, terminal: terminal) }

      it "builds a TTY prompt on the terminal" do
        expect(prompt.send(:backend)).to be_a(TTY::Prompt)
      end
    end
  end
end
