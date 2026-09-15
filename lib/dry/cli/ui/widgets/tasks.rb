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
        # Every task is given a {Line}. Its detail is drawn after the task's
        # name while it runs, on an animated terminal. A task that calls
        # {Line#fail} is marked failed with its reason, as is every group above
        # it, and the rest of the tree runs on.
        #
        # When a task raises, it and every group above it are marked failed,
        # tasks already running beside it finish, everything that had not
        # started is marked skipped, and the error is re-raised.
        #
        # @example
        #   ui.tasks("Deploy") do |t|
        #     t.task("Build assets") { build }
        #     t.group("Migrate", concurrent: 2) do |g|
        #       g.task("users") { |line| migrate(:users) { |table| line.detail = table } }
        #       g.task("orders") { migrate(:orders) }
        #     end
        #   end
        class Tasks
          # Frames a running task cycles through on an animated terminal.
          FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

          # Seconds between spinner frames.
          INTERVAL = 0.1

          # Checks a `concurrent:` setting.
          #
          # @param value [Boolean, Integer] true for all at once, false for one
          #   at a time, or the most that may run at once
          # @return [Boolean, Integer] the value
          # @raise [ArgumentError] for anything else
          def self.concurrency(value)
            return value if [true, false].include?(value) || (value.is_a?(Integer) && value.positive?)

            raise ArgumentError, "concurrent must be true, false or a positive Integer, got #{value.inspect}"
          end

          # One task, or a group of them.
          class Node
            # @param name [String]
            # @param job [Proc, nil] the work; nil for a group
            # @param concurrent [Boolean, Integer] whether, or how many of, a
            #   group's tasks run at once
            def initialize(name, job = nil, concurrent: false)
              @name = name
              @job = job
              @concurrent = concurrent
              @children = []
              @state = :pending
              @seconds = nil
              @line = Line.new
            end

            # @return [String]
            attr_reader :name

            # @return [Proc, nil]
            attr_reader :job

            # @return [Boolean, Integer]
            attr_reader :concurrent

            # @return [Line] what the task's work reports through
            attr_reader :line

            # @return [Array<Node>]
            attr_reader :children

            # @return [Symbol] one of the keys of {Theme::STATES}
            attr_accessor :state

            # @return [Float, nil] how long the node ran, once it has finished
            attr_accessor :seconds

            # @return [Boolean] whether this node holds tasks rather than work
            def group? = job.nil?

            # Whether the work reported a failure without raising: through its
            # line, or for a group, through any of its children.
            #
            # @return [Boolean]
            def failed?
              group? ? children.any? { |child| child.state == :failed } : line.failed?
            end

            # @return [String] the name, with the reason once the work has failed
            def label = line.summary(name)
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
            # @yieldparam line [Line] reports on the work while it runs
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
            # @param concurrent [Boolean, Integer] run the group's tasks at the
            #   same time: all of them, or at most this many
            # @yieldparam group [Builder] declares the tasks inside the group
            # @return [self]
            # @raise [ArgumentError] without a block, or with an invalid concurrent
            def group(name, concurrent: false)
              raise ArgumentError, "group #{name.inspect} needs a block" unless block_given?

              node = Node.new(name, concurrent: Tasks.concurrency(concurrent))
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
          # @param concurrent [Boolean, Integer] run the top-level tasks at the
          #   same time: all of them, or at most this many
          # @yieldparam tasks [Builder]
          # @return [nil]
          # @raise [ArgumentError] with an invalid concurrent
          def run(title = nil, concurrent: false)
            Tasks.concurrency(concurrent)
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
          # @param concurrent [Boolean, Integer]
          # @return [void]
          def run_all(nodes, concurrent)
            return nodes.each { |node| execute(node) } unless concurrent

            futures = concurrent == true ? all_at_once(nodes) : at_most(concurrent, nodes)
            futures.each(&:wait)
            failed = futures.find(&:rejected?)
            raise failed.reason if failed
          end

          # @param nodes [Array<Node>]
          # @return [Array<Concurrent::Promises::Future>] one per node
          def all_at_once(nodes)
            nodes.map { |node| Concurrent::Promises.future(node) { |each| execute(each) } }
          end

          # Workers that take nodes off a queue until it is empty, or until
          # one of them raises. A node no worker took stays pending, and is
          # marked skipped once the tree ends.
          #
          # @param limit [Integer]
          # @param nodes [Array<Node>]
          # @return [Array<Concurrent::Promises::Future>] one per worker
          def at_most(limit, nodes)
            queue = Queue.new
            nodes.each { |node| queue << node }
            queue.close
            stop = Concurrent::AtomicBoolean.new
            Array.new([limit, nodes.size].min) { Concurrent::Promises.future { work(queue, stop) } }
          end

          # @param queue [Queue] closed, so `pop` returns nil once it is empty
          # @param stop [Concurrent::AtomicBoolean] set once any worker raises
          # @return [void]
          def work(queue, stop)
            ok = false
            while (node = queue.pop) && stop.false?
              execute(node)
            end
            ok = true
          ensure
            stop.make_true unless ok
          end

          # @param node [Node]
          # @return [void]
          def execute(node)
            started = clock.call
            change(node, :running)
            ok = false
            node.group? ? run_all(node.children, node.concurrent) : Line.call(node.job, node.line)
            ok = !node.failed?
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
            "#{pastel.bright_black(rows.fetch(node))}#{pastel.decorate(glyph, color)} #{text(node)}#{elapsed}"
          end

          # What follows the glyph: the name, then the detail while the task
          # runs, or the reason once it has failed.
          #
          # @param node [Node]
          # @return [String]
          def text(node)
            detail = node.line.detail
            return node.label unless node.state == :running && !detail.empty?

            "#{node.name} #{detail}"
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
