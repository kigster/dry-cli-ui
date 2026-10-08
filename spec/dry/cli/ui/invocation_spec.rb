# frozen_string_literal: true

require "tmpdir"

RSpec.describe Dry::CLI::UI::Invocation do
  let(:started_at) { Time.new(2026, 10, 8, 9, 5, 7) }
  let(:tmp) { Dir.mktmpdir }
  let(:directory) { tmp }

  after { FileUtils.rm_rf(tmp) }

  describe ".for" do
    subject(:invocation) { described_class.for(command, program: "/usr/local/bin/law-cli", started_at: started_at, directory: directory) }

    context "without a command" do
      let(:command) { nil }

      its(:executable) { is_expected.to eq("law-cli") }
      its(:action) { is_expected.to be_nil }
      its(:name) { is_expected.to eq("law-cli") }
      its(:basename) { is_expected.to eq("law-cli") }
      its(:started_at) { is_expected.to eq(started_at) }
      its(:directory) { is_expected.to eq(directory) }
    end

    context "with a command dry-cli resolved by name" do
      let(:command) { Object.new.tap { it.instance_variable_set(:@ui_command_names, %w[generate text]) } }

      its(:action) { is_expected.to eq("generate-text") }
      its(:name) { is_expected.to eq("Object") }
      its(:basename) { is_expected.to eq("law-cli-generate-text") }
    end

    context "with the only command of a CLI" do
      let(:command) { Object.new.tap { it.instance_variable_set(:@ui_command_names, []) } }

      its(:action) { is_expected.to eq("") }
      its(:basename) { is_expected.to eq("law-cli") }
    end

    context "with a command dry-cli did not name" do
      let(:command) { stub_const("Law::Commands::GenerateText", Class.new).new }

      its(:action) { is_expected.to eq("generate-text") }
      its(:name) { is_expected.to eq("Law::Commands::GenerateText") }
    end

    context "with an anonymous command" do
      let(:command) { Class.new.new }

      its(:action) { is_expected.to be_nil }
      its(:name) { is_expected.to eq("law-cli") }
    end

    context "with the defaults" do
      subject(:invocation) { described_class.for }

      its(:executable) { is_expected.to eq(File.basename($PROGRAM_NAME)) }
      its(:started_at) { is_expected.to eq(Dry::CLI::UI.started_at) }
      its(:directory) { is_expected.to eq(Dir.pwd) }
    end
  end

  describe ".root" do
    subject { described_class.root(File.join(tmp, "a", "b")) }

    before { FileUtils.mkdir_p(File.join(tmp, "a", "b")) }

    context "inside a repository" do
      before { FileUtils.mkdir_p(File.join(tmp, "a", ".git")) }

      it { is_expected.to eq(File.join(tmp, "a")) }
    end

    context "inside a worktree, whose .git is a file" do
      before { File.write(File.join(tmp, "a", "b", ".git"), "gitdir: elsewhere\n") }

      it { is_expected.to eq(File.join(tmp, "a", "b")) }
    end

    context "outside any repository" do
      it { is_expected.to eq(File.join(tmp, "a", "b")) }
    end
  end

  describe "paths" do
    subject(:invocation) do
      described_class.new(executable: "law-cli", action: "generate-text", name: "X", started_at: started_at, directory: directory)
    end

    let(:directory) { File.join(tmp, "sub") }

    before do
      FileUtils.mkdir_p(File.join(tmp, ".git"))
      FileUtils.mkdir_p(directory)
    end

    describe "#report_path" do
      it { expect(invocation.report_path(nil)).to be_nil }
      it { expect(invocation.report_path("-")).to be_nil }
      it { expect(invocation.report_path("")).to eq(File.join(tmp, "log", "law-cli-generate-text.2026-10-08.090507.log")) }
      it { expect(invocation.report_path("out/report.txt")).to eq(File.join(directory, "out", "report.txt")) }

      it "creates the directory the file goes in" do
        expect { invocation.report_path("") }.to change { File.directory?(File.join(tmp, "log")) }.from(false).to(true)
      end
    end

    describe "#log_path" do
      it { expect(invocation.log_path(nil)).to be_nil }
      it { expect(invocation.log_path("-")).to eq("-") }
      it { expect(invocation.log_path("")).to eq(File.join(tmp, "log", "law-cli-generate-text.log")) }
      it { expect(invocation.log_path(File.join(tmp, "x.log"))).to eq(File.join(tmp, "x.log")) }
    end
  end
end
