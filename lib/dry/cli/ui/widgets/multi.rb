# frozen_string_literal: true

require "concurrent"

module Dry
  class CLI
    module UI
      module Widgets
        # Runs several named jobs, by default all at once, under one headline,
        # and shows the state of each on a row of its own. {MultiSpinner} and
        # {MultiProgress} decide what a row says; this class runs the jobs and
        # draws the rows.
        #
        # The block only declares the jobs; nothing runs until it returns, so
        # every row, including those of jobs still waiting under a concurrency
        # limit, is drawn before the first job starts.
        #
        # On an animated terminal the rows are drawn once and redrawn in place.
        # When there are more rows than the screen has, only the jobs running
        # are shown under the headline, as many as fit. Without animation it
        # prints `Title...`, then each job's outcome as it ends, then the headline's.
        #
        # Given a {Stop} that is set, jobs already running finish, jobs not yet
        # started are marked skipped, and so is the headline; while the running
        # jobs finish, the headline says `stopping`.
        #
        # When a job raises, jobs already running finish, jobs not yet started
        # are marked skipped, the headline is marked failed, and the first error
        # is re-raised.
        class Multi
          # What a job's row is prefixed with when rows are printed one by one.
          PLAIN_INDENT = "  "

          # One declared job.
          class Job
            # @param label [String]
            # @param work [Proc]
            # @param handle [Object] what the work is given to report through
            def initialize(label, work, handle)
              @label = label
              @work = work
              @handle = handle
              @state = :pending
            end

            # @return [String]
            attr_reader :label

            # @return [Proc]
            attr_reader :work

            # @return [Object] a {Line} or a {Progress::Handle}
            attr_reader :handle

            # @return [Symbol] one of the keys of {Theme::STATES}
            attr_accessor :state

            # @return [Float, nil] when the job started, by the widget's clock
            attr_accessor :started

            # @return [Float, nil] how long the job ran, once it has ended
            attr_accessor :seconds

            # @return [Object] what the work returned
            attr_accessor :value
          end

          # @param terminal [Terminal]
          # @param clock [#call] returns monotonic seconds
          # @param config [Configuration] where the spinner frames come from
          def initialize(terminal, clock:, config: UI.config)
            @terminal = terminal
            @clock = clock
            @config = config
            @jobs = []
            @state = :pending
            @live = nil
            @lock = Mutex.new
            @frame = 0
            @drawn = 0
          end

          # Declares the jobs with the block, then runs them.
          #
          # @param title [String] the headline above the jobs
          # @param concurrent [Boolean, Integer] all at once, one at a time, or
          #   at most this many at once
          # @param stop [Stop, nil] once set, no more jobs start
          # @yieldparam builder [Object] declares the jobs
          # @return [Array<Object>] what each job returned, in declaration
          #   order; nil for a job that never ran
          # @raise [ArgumentError] with an invalid concurrent
          # @raise [Exception] the first error a job raised
          def run(title, concurrent: true, stop: nil)
            Pool.concurrency(concurrent)
            yield builder
            @title = title
            @stop = stop
            @started = clock.call
            ticker = start
            begin
              Pool.run(jobs, concurrent, stop: stop) { |job| execute(job) }
            ensure
              ticker&.shutdown
              ticker&.wait_for_termination(1)
              finish
            end
            jobs.map(&:value)
          end

          private

          # @return [Terminal]
          attr_reader :terminal

          # @return [#call]
          attr_reader :clock

          # @return [Configuration]
          attr_reader :config

          # @return [Array<Job>]
          attr_reader :jobs

          # @return [String]
          attr_reader :title

          # @return [Stop, nil]
          attr_reader :stop

          # @return [Float] when the headline started, by the clock
          attr_reader :started

          # @return [Mutex] held while a row changes or the rows are drawn
          attr_reader :lock

          # @return [Symbol] the headline's state
          attr_accessor :state

          # @return [Integer] the spinner frame to draw next
          attr_accessor :frame

          # @return [Object] what the declaration block is given: the
          #   subclass's Builder, appending to {#jobs}
          def builder = self.class::Builder.new(jobs)

          # Runs a job's work with its handle.
          #
          # @param job [Job]
          # @return [Object] what the work returns
          def call(job) = job.work.call(job.handle)

          # @param job [Job]
          # @return [#current, #total, nil] what a status bar reads the job's progress from
          def progress_of(_job) = nil

          # @param job [Job]
          # @return [Boolean] whether the work reported a failure without raising
          def reported_failure?(_job) = false

          # What follows a running job's glyph.
          #
          # @param job [Job]
          # @param width [Integer] the columns its label is padded to
          # @return [String]
          def running(job, _width) = job.label

          # What follows a job's glyph once it has ended.
          #
          # @param job [Job]
          # @return [String]
          def summary(job) = job.label

          # What follows the headline's glyph while jobs run.
          #
          # @param width [Integer] the columns the title is padded to
          # @return [String]
          def running_headline(_width) = title

          # What follows the headline's glyph once every job has ended.
          #
          # @return [String]
          def headline_summary = title

          # Draws every row and starts the spinners turning when live, or
          # prints the title otherwise.
          #
          # @return [Concurrent::TimerTask, nil]
          def start
            self.state = :running
            unless live?
              terminal.puts("#{title}...")
              return
            end

            drawn = rows
            drawn.each { |row| terminal.puts(row) }
            @drawn = drawn.size
            Concurrent::TimerTask.new(execution_interval: config.spinner_frame_seconds) { tick }.tap(&:execute)
          end

          # @param job [Job]
          # @return [void]
          def execute(job)
            job.started = clock.call
            terminal.started(job, job.label, progress: progress_of(job))
            change(job, :running)
            ok = false
            job.value = call(job)
            ok = !reported_failure?(job)
          ensure
            terminal.finished(job, ok)
            change(job, ok ? :done : :failed, seconds: clock.call - job.started)
          end

          # Marks jobs that never started as skipped, and ends the headline.
          #
          # @return [void]
          def finish
            jobs.each { |job| change(job, :skipped) if job.state == :pending }
            lock.synchronize do
              self.state = outcome
              @seconds = clock.call - started
              live? ? redraw : terminal.puts(Outcome.line(terminal, state, headline_summary, @seconds))
            end
          end

          # @return [Symbol] the headline's state once every job has ended:
          #   failed when any job failed, skipped when any was skipped
          def outcome
            states = jobs.map(&:state)
            return :failed if states.include?(:failed)

            states.include?(:skipped) ? :skipped : :done
          end

          # @param job [Job]
          # @param state [Symbol]
          # @param seconds [Float, nil]
          # @return [void]
          def change(job, state, seconds: nil)
            lock.synchronize do
              job.state = state
              job.seconds = seconds
              if live?
                redraw
              elsif state != :running
                terminal.puts("#{PLAIN_INDENT}#{row(job, 0)}")
              end
            end
          end

          # Whether to redraw in place, which needs cursor movement.
          #
          # @return [Boolean]
          def live?
            @live = terminal.animated? if @live.nil?
            @live
          end

          # Whether some rows must be left out, since the cursor cannot move
          # above the top row of the screen.
          #
          # @return [Boolean]
          def crowded?
            @crowded = jobs.size + 1 >= terminal.height if @crowded.nil?
            @crowded
          end

          # @return [void]
          def tick
            lock.synchronize do
              self.frame += 1
              redraw
            end
          end

          # Draws the rows over the ones drawn last, clearing the screen below
          # first, since there may be fewer rows than before.
          #
          # @return [void]
          def redraw
            drawn = rows
            terminal.print(terminal.cursor.up(@drawn) + terminal.cursor.clear_screen_down + drawn.map { |row| "#{terminal.cursor.clear_line}#{row}\n" }.join)
            @drawn = drawn.size
          end

          # The headline, then one row per job shown, with its tree branch.
          #
          # @return [Array<String>]
          def rows
            width = label_width
            shown = visible
            branches = shown.each_index.map { |index| index == shown.size - 1 ? "└─ " : "├─ " }
            [headline(width), *shown.zip(branches).map { |job, branch| terminal.pastel.bright_black(branch) + row(job, width - branch.length) }]
          end

          # Every job; when crowded, only the running ones, as many as leave
          # the bottom row free.
          #
          # @return [Array<Job>]
          def visible
            return jobs unless crowded?

            jobs.select { |job| job.state == :running }.first([terminal.height - 2, 0].max)
          end

          # The columns every label is padded to, so what follows lines up.
          #
          # @return [Integer]
          def label_width
            [title.length, *jobs.map { |job| job.label.length + 3 }].max
          end

          # @param width [Integer]
          # @return [String]
          def headline(width)
            return "#{glyph(state)} #{running_headline(width)}#{stopping}" if state == :running

            elapsed = " #{terminal.pastel.bright_black("(#{Duration.format(@seconds)})")}"
            "#{glyph(state)} #{headline_summary}#{elapsed}"
          end

          # @return [String] ` stopping` once a stop is asked for, or nothing
          def stopping = stop&.stopped? ? " #{terminal.pastel.yellow('stopping')}" : ""

          # @param job [Job]
          # @param width [Integer] the columns its label is padded to
          # @return [String]
          def row(job, width)
            return "#{glyph(:running)} #{running(job, width)}" if job.state == :running

            elapsed = " #{terminal.pastel.bright_black("(#{Duration.format(job.seconds)})")}" if job.seconds
            "#{glyph(job.state)} #{job.state == :pending ? job.label : summary(job)}#{elapsed}"
          end

          # A state's marker, `[✓]`; a turning spinner, `[⠏]`, for a running row, live.
          #
          # @param state [Symbol]
          # @return [String]
          def glyph(state)
            frames = config.spinner_frames
            Theme.marker(terminal.pastel, state, (frames[frame % frames.size] if state == :running && live?))
          end
        end
      end
    end
  end
end
