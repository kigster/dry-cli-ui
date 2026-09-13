# frozen_string_literal: true

require "concurrent"

module Dry
  class CLI
    module UI
      module Widgets
        # Runs a tree of named tasks and shows the state of each: pending,
        # running, done, failed or skipped, with elapsed times.
        #
        # The block only declares the tree; nothing runs until it returns, so
        # the whole shape is known before the first task starts. Tasks run in
        # order, except inside a group declared `concurrent: true`, whose
        # tasks all run at once.
        #
        # On an animated terminal the tree is drawn once and redrawn in place,
        # with a spinner beside every running task. Otherwise, or when the
        # tree is taller than the screen, each line is printed once it has
        # something final to say.
        #
        # When a task raises, it and every group above it are marked failed,
        # tasks already running beside it finish, everything that had not
        # started is marked skipped, and the error is re-raised.
        #
        # @example
        #   ui.tasks("Deploy") do |t|
        #     t.task("Build assets") { build }
        #     t.group("Migrate", concurrent: true) do |g|
        #       g.task("users") { migrate(:users) }
        #       g.task("orders") { migrate(:orders) }
        #     end
        #   end
        class Tasks
          # Frames a running task cycles through on an animated terminal.
          FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

          # Seconds between spinner frames.
          INTERVAL = 0.1

          # One task, or a group of them.
          class Node
            # @param name [String]
            # @param job [Proc, nil] the work; nil for a group
            # @param concurrent [Boolean] whether a group runs its tasks at once
            def initialize(name, job = nil, concurrent: false)
              @name = name
              @job = job
              @concurrent = concurrent
              @children = []
              @state = :pending
              @seconds = nil
            end

            # @return [String]
            attr_reader :name

            # @return [Proc, nil]
            attr_reader :job

            # @return [Boolean]
            attr_reader :concurrent
            alias concurrent? concurrent

            # @return [Array<Node>]
            attr_reader :children

            # @return [Symbol] one of the keys of {Theme::STATES}
            attr_accessor :state

            # @return [Float, nil] how long the node ran, once it has finished
            attr_accessor :seconds

            # @return [Boolean] whether this node holds tasks rather than work
            def group? = job.nil?
          end

          # What the declaration block is given.
          class Builder
            # @param nodes [Array<Node>] the list new nodes are appended to
            def initialize(nodes)
              @nodes = nodes
            end

            # Declares a task.
            #
            # @param name [String]
            # @yield the work
            # @return [self]
            # @raise [ArgumentError] without a block
            def task(name, &job)
              raise ArgumentError, "task #{name.inspect} needs a block" unless job

              nodes << Node.new(name, job)
              self
            end

            # Declares a group of tasks.
            #
            # @param name [String]
            # @param concurrent [Boolean] run the group's tasks at the same time
            # @yieldparam group [Builder] declares the tasks inside the group
            # @return [self]
            # @raise [ArgumentError] without a block
            def group(name, concurrent: false)
              raise ArgumentError, "group #{name.inspect} needs a block" unless block_given?

              node = Node.new(name, concurrent: concurrent)
              nodes << node
              yield Builder.new(node.children)
              self
            end

            private

            # @return [Array<Node>]
            attr_reader :nodes
          end

          # @param terminal [Terminal]
          # @param clock [#call] returns monotonic seconds
          def initialize(terminal, clock:)
            @terminal = terminal
            @clock = clock
            @roots = []
            @live = nil
            @lock = Mutex.new
            @frame = 0
          end

          # Declares the tree with the block, then runs it.
          #
          # @param title [String, nil] a heading printed above the tree
          # @param concurrent [Boolean] run the top-level tasks at the same time
          # @yieldparam tasks [Builder]
          # @return [nil]
          def run(title = nil, concurrent: false)
            yield Builder.new(roots)
            terminal.puts(terminal.pastel.bold(title)) if title
            ticker = start_ticker
            begin
              run_all(roots, concurrent)
            ensure
              ticker&.shutdown
              ticker&.wait_for_termination(1)
              skip_pending
            end
            nil
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @return [Array<Node>]
          attr_reader :roots

          # @return [Mutex] held while the tree changes or is drawn
          attr_reader :lock

          # @return [Integer] the spinner frame to draw next
          attr_accessor :frame

          # @param nodes [Array<Node>]
          # @param concurrent [Boolean]
          # @return [void]
          def run_all(nodes, concurrent)
            return nodes.each { |node| execute(node) } unless concurrent

            futures = nodes.map { |node| Concurrent::Promises.future(node) { |each| execute(each) } }
            futures.each(&:wait)
            failed = futures.find(&:rejected?)
            raise failed.reason if failed
          end

          # @param node [Node]
          # @return [void]
          def execute(node)
            started = clock.call
            change(node, :running)
            ok = false
            node.group? ? run_all(node.children, node.concurrent?) : node.job.call
            ok = true
          ensure
            change(node, ok ? :done : :failed, seconds: clock.call - started)
          end

          # @return [void]
          def skip_pending
            rows.each_key { |node| change(node, :skipped) if node.state == :pending }
          end

          # @param node [Node]
          # @param state [Symbol]
          # @param seconds [Float, nil]
          # @return [void]
          def change(node, state, seconds: nil)
            lock.synchronize do
              node.state = state
              node.seconds = seconds
              if live?
                redraw
              elsif settled?(node)
                terminal.puts(line(node))
              end
            end
          end

          # Whether a node has reached the state plain output reports: a group
          # once it starts, so its children appear beneath it, and a task once
          # it ends.
          #
          # @param node [Node]
          # @return [Boolean]
          def settled?(node)
            return true if node.state == :skipped

            node.group? ? node.state == :running : node.state != :running
          end

          # Whether to redraw in place. Needs cursor movement, and a tree that
          # fits on screen: the cursor cannot move above the top row.
          #
          # @return [Boolean]
          def live?
            @live = terminal.animated? && rows.size < terminal.height if @live.nil?
            @live
          end

          # Draws the tree and starts turning the spinners, when live.
          #
          # @return [Concurrent::TimerTask, nil]
          def start_ticker
            return unless live?

            rows.each_key { |node| terminal.puts(line(node)) }
            Concurrent::TimerTask.new(execution_interval: INTERVAL) { tick }.tap(&:execute)
          end

          # @return [void]
          def tick
            lock.synchronize do
              self.frame += 1
              redraw
            end
          end

          # @return [void]
          def redraw
            terminal.print(terminal.cursor.up(rows.size))
            rows.each_key { |node| terminal.print("#{terminal.cursor.clear_line}#{line(node)}\n") }
          end

          # @param node [Node]
          # @return [String]
          def line(node)
            pastel = terminal.pastel
            glyph, color = Theme::STATES.fetch(node.state)
            glyph = FRAMES[frame % FRAMES.size] if node.state == :running && live?
            elapsed = " #{pastel.bright_black("(#{Duration.format(node.seconds)})")}" if node.seconds
            "#{pastel.bright_black(rows.fetch(node))}#{pastel.decorate(glyph, color)} #{node.name}#{elapsed}"
          end

          # Every node in display order, with the tree branch drawn before it.
          #
          # @return [Hash{Node => String}]
          def rows
            @rows ||= layout(roots, "", {})
          end

          # @param nodes [Array<Node>]
          # @param prefix [String]
          # @param acc [Hash{Node => String}]
          # @return [Hash{Node => String}]
          def layout(nodes, prefix, acc)
            nodes.each_with_index do |node, index|
              last = index == nodes.size - 1
              acc[node] = "#{prefix}#{last ? '└─ ' : '├─ '}"
              layout(node.children, "#{prefix}#{last ? '   ' : '│  '}", acc)
            end
            acc
          end
        end
      end
    end
  end
end
