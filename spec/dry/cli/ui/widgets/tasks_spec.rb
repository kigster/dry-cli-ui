# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Widgets::Tasks do
  subject(:tasks) { described_class.new(terminal, clock: FakeClock.new) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(io, env: {}, width: 80) }
  let(:ran) { [] }
  let(:deploy) do
    lambda do |t|
      t.task("Build") { ran << :build }
      t.group("Migrate") do |g|
        g.task("users") { ran << :users }
        g.task("orders") { ran << :orders }
      end
      t.task("Restart") { ran << :restart }
    end
  end

  context "on a pipe" do
    let(:io) { StringIO.new }

    it "runs every task in order and returns nil" do
      expect(tasks.run("Deploy", &deploy)).to be_nil
      expect(ran).to eq(%i[build users orders restart])
    end

    it "prints each line once it is final" do
      tasks.run("Deploy", &deploy)
      expect(io.string).to eq(<<~TREE)
        Deploy
        ├─ ✓ Build (0.5s)
        ├─ ▸ Migrate
        │  ├─ ✓ users (0.5s)
        │  └─ ✓ orders (0.5s)
        └─ ✓ Restart (0.5s)
      TREE
    end

    it "prints no heading without a title" do
      tasks.run { |t| t.task("Build") { nil } }
      expect(io.string).to eq("└─ ✓ Build (0.5s)\n")
    end

    context "when a task fails" do
      let(:deploy) do
        lambda do |t|
          t.task("Build") { nil }
          t.group("Migrate") do |g|
            g.task("users") { raise "Missing dependency: taxable_income" }
            g.task("orders") { ran << :orders }
          end
          t.task("Restart") { ran << :restart }
        end
      end

      before do
        expect { tasks.run("Deploy", &deploy) }.to raise_error(RuntimeError, "Missing dependency: taxable_income")
      end

      it { expect(ran).to be_empty }

      it "marks it failed and everything after it skipped" do
        expect(io.string).to eq(<<~TREE)
          Deploy
          ├─ ✓ Build (0.5s)
          ├─ ▸ Migrate
          │  ├─ ✗ users (0.5s)
          │  └─ – orders
          └─ – Restart
        TREE
      end
    end

    it "gives each task a line" do
      lines = []
      tasks.run { |t| t.task("Build") { |line| lines << line } }
      expect(lines).to contain_exactly(an_instance_of(Dry::CLI::UI::Line))
    end

    it "runs a lambda task that takes no line" do
      tasks.run { |t| t.task("Build", &-> { ran << :build }) }
      expect(ran).to eq([:build])
    end

    it "keeps a task's detail to itself" do
      tasks.run { |t| t.task("Build") { |line| line.detail = "assets" } }
      expect(io.string).to eq("└─ ✓ Build (0.5s)\n")
    end

    context "when a task reports a failure" do
      before do
        tasks.run("Deploy") do |t|
          t.group("Migrate") do |g|
            g.task("users") { |line| line.fail("Missing dependency: taxable_income") }
            g.task("orders") { ran << :orders }
          end
          t.task("Restart") { ran << :restart }
        end
      end

      it { expect(ran).to eq(%i[orders restart]) }

      it "marks it failed with its reason and runs the rest" do
        expect(io.string).to eq(<<~TREE)
          Deploy
          ├─ ▸ Migrate
          │  ├─ ✗ users: Missing dependency: taxable_income (0.5s)
          │  └─ ✓ orders (0.5s)
          └─ ✓ Restart (0.5s)
        TREE
      end
    end

    describe "a concurrency limit" do
      let(:running) { Concurrent::AtomicFixnum.new }
      let(:peak) { Concurrent::AtomicFixnum.new }
      let(:work) do
        lambda do |name|
          now = running.increment
          peak.update { |seen| [seen, now].max }
          sleep(0.05)
          running.decrement
          ran << name
        end
      end

      it "runs at most that many tasks at once" do
        tasks.run(concurrent: 2) do |t|
          %i[a b c d e].each { |name| t.task(name.to_s) { work.(name) } }
        end
        expect(ran).to contain_exactly(:a, :b, :c, :d, :e)
        expect(peak.value).to eq(2)
      end

      it "limits a group's tasks too" do
        tasks.run do |t|
          t.group("Fetch", concurrent: 3) { |g| %i[a b c d].each { |name| g.task(name.to_s) { work.(name) } } }
        end
        expect(peak.value).to eq(3)
      end

      it "starts nothing more once a task raises, and skips what never started" do
        expect do
          tasks.run(concurrent: 1) do |t|
            t.task("a") { raise "offline" }
            t.task("b") { ran << :b }
          end
        end.to raise_error(RuntimeError, "offline")
        expect(ran).to be_empty
        expect(io.string).to eq("├─ ✗ a (0.5s)\n└─ – b\n")
      end

      [0, -1, 1.5, "2", nil].each do |limit|
        it "refuses #{limit.inspect} for the tree" do
          expect { tasks.run(concurrent: limit) { |t| t.task("a") { nil } } }
            .to raise_error(ArgumentError, /concurrent must be true, false or a positive Integer/)
        end

        it "refuses #{limit.inspect} for a group" do
          expect { tasks.run { |t| t.group("g", concurrent: limit) { |g| g.task("a") { nil } } } }
            .to raise_error(ArgumentError, /concurrent must be true, false or a positive Integer/)
        end
      end
    end

    it "draws nothing when the declaration itself fails" do
      expect { tasks.run { |t| t.task("Build") } }.to raise_error(ArgumentError, /needs a block/)
      expect(io.string).to be_empty
    end

    it "requires a block for a group" do
      expect { tasks.run { |t| t.group("Migrate") } }.to raise_error(ArgumentError, /group "Migrate" needs a block/)
    end

    it "completes an empty group" do
      tasks.run { |t| t.group("Nothing") { |_| nil } }
      expect(io.string).to eq("└─ ▸ Nothing\n")
    end

    context "with a concurrent group" do
      # Each task waits until both have started, so running them one after
      # the other fails instead of passing on timing luck.
      let(:latch) { Concurrent::CountDownLatch.new(2) }
      let(:rendezvous) do
        lambda do |name|
          latch.count_down
          raise "#{name} ran alone" unless latch.wait(2)

          ran << name
        end
      end

      it "runs its tasks at the same time" do
        tasks.run do |t|
          t.group("Fetch", concurrent: true) do |g|
            g.task("fonts") { rendezvous.(:fonts) }
            g.task("images") { rendezvous.(:images) }
          end
          t.task("Publish") { ran << :publish }
        end
        expect(ran).to contain_exactly(:fonts, :images, :publish)
        expect(ran.last).to eq(:publish)
        expect(io.string).to include("├─ ▸ Fetch\n", "│  ├─ ✓ fonts (", "│  └─ ✓ images (", "└─ ✓ Publish (")
      end

      it "runs top-level tasks at the same time" do
        tasks.run(concurrent: true) do |t|
          t.task("fonts") { rendezvous.(:fonts) }
          t.task("images") { rendezvous.(:images) }
        end
        expect(ran).to contain_exactly(:fonts, :images)
      end

      it "lets the other tasks finish when one fails, then skips the rest" do
        expect do
          tasks.run do |t|
            t.group("Fetch", concurrent: true) do |g|
              g.task("fonts") do
                latch.count_down
                raise "offline"
              end
              g.task("images") { rendezvous.(:images) }
            end
            t.task("Publish") { ran << :publish }
          end
        end.to raise_error(RuntimeError, "offline")
        expect(ran).to eq([:images])
        expect(io.string).to include("│  ├─ ✗ fonts (", "│  └─ ✓ images (", "└─ – Publish\n")
      end
    end
  end

  context "on a terminal" do
    let(:io) { FakeTTY.new }

    before { allow(TTY::Screen).to receive(:height).and_return(height) }

    context "when the tree fits" do
      let(:height) { 24 }

      before { tasks.run("Deploy", &deploy) }

      it "draws the tree pending, then redraws it in place" do
        expect(plain(io.string)).to start_with("Deploy\n├─ ○ Build\n├─ ○ Migrate\n│  ├─ ○ users\n")
        expect(io.string).to include("\e[5A")
      end

      it "shows a spinner beside the running task" do
        expect(plain(io.string)).to include("├─ ⠋ Build\n")
      end

      it "ends with every task done" do
        expect(plain(io.string)).to end_with(<<~TREE)
          ├─ ✓ Build (0.5s)
          ├─ ✓ Migrate (2.5s)
          │  ├─ ✓ users (0.5s)
          │  └─ ✓ orders (0.5s)
          └─ ✓ Restart (0.5s)
        TREE
      end
    end

    context "when a task says what it is doing" do
      let(:height) { 24 }

      before do
        tasks.run do |t|
          t.group("Migrate") do |g|
            g.task("users") do |line|
              line.detail = "table 3 of 7"
              sleep(1.5 * described_class::INTERVAL)
              line.fail("locked")
            end
          end
        end
      end

      it "draws the detail after the running task" do
        expect(plain(io.string)).to include("   └─ ⠙ users table 3 of 7\n")
      end

      it "ends with the task and its group failed, and the reason instead of the detail" do
        expect(plain(io.string)).to end_with("└─ ✗ Migrate (1.5s)\n   └─ ✗ users: locked (0.5s)\n")
      end
    end

    context "while a task takes a while" do
      let(:height) { 24 }

      before { tasks.run { |t| t.task("Compile") { sleep(3.5 * described_class::INTERVAL) } } }

      it "turns the spinner" do
        expect(plain(io.string)).to include("└─ ⠙ Compile\n")
      end
    end

    context "when the tree is taller than the screen" do
      let(:height) { 3 }

      before { tasks.run("Deploy", &deploy) }

      it "prints lines as they become final, without moving the cursor" do
        expect(io.string).not_to include("\e[5A")
        expect(plain(io.string)).to include("├─ ▸ Migrate\n")
      end
    end
  end
end
