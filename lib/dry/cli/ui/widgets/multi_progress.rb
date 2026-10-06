# frozen_string_literal: true

module Dry
  class CLI
    module UI
      module Widgets
        # Several progress bars under one headline bar that counts them all,
        # like TTY::ProgressBar::Multi. Each job is given a {Progress::Handle}.
        #
        # Every row shows a bar, a percentage, a count and an ETA while its job
        # runs, and is replaced by `✓ label 120/120 (1.1s)` when it ends. The
        # bar's characters come from {Configuration#bar_format}.
        #
        # A job declared with `spinner` instead has no bar: its row turns and
        # shows its {Line}'s detail, as in {MultiSpinner}, and ends
        # `✓ label (0.4s)`. It suits a phase whose size is never known, among
        # phases whose size is. It counts as a job and as no units, so a
        # headline over such rows reads best with `count: :jobs`.
        #
        # @example
        #   ui.multi_progress("Downloading") do |m|
        #     files.each do |file|
        #       m.progress(file.name, total: file.size, color: file.large? ? :yellow : nil) do |bar|
        #         download(file) { |bytes| bar.advance(bytes) }
        #       end
        #     end
        #   end
        #
        # @example Phases, one at a time, some of known size
        #   ui.multi_progress("Generating", concurrent: false, count: :jobs) do |m|
        #     m.spinner("Finding") { |line| found = find { |dir| line.detail = dir } }
        #     m.progress("Extracting", total: nil) { |bar| bar.total = found.size; found.each { extract(it) && bar.advance } }
        #     m.spinner("Indexing") { index }
        #   end
        #
        # See {Multi} for how the jobs run and how the rows are drawn.
        class MultiProgress < Multi
          # What the declaration block is given.
          class Builder
            # @param jobs [Array<Multi::Job>] the list new jobs are appended to
            def initialize(jobs)
              @jobs = jobs
            end

            # Declares a job with a progress bar of its own.
            #
            # @param label [String]
            # @param total [Integer, nil] units of work; nil when the job finds
            #   out as it runs, and sets `total=` on its handle
            # @param color [Symbol, nil] the finished part's Pastel style; nil for
            #   {Configuration#bar_color}
            # @yieldparam progress [Progress::Handle] call `advance` as units complete
            # @return [self]
            # @raise [ArgumentError] without a block, when total is neither nil
            #   nor a non-negative Integer, or when color is not a Pastel style
            def progress(label, total:, color: nil, &work)
              raise ArgumentError, "progress #{label.inspect} needs a block" unless work

              Progress.total(total) unless total.nil?

              @jobs << Multi::Job.new(label, work, Progress::Handle.new(total, nil, color: Progress.color(color)))
              self
            end

            # Declares a job with a spinner in place of a bar, for work whose
            # size is never known.
            #
            # @param label [String]
            # @yieldparam line [Line] reports on the work while it runs
            # @return [self]
            # @raise [ArgumentError] without a block
            def spinner(label, &work)
              raise ArgumentError, "spinner #{label.inspect} needs a block" unless work

              @jobs << Multi::Job.new(label, work, Line.new)
              self
            end
          end

          # What the headline bar can count.
          COUNTS = %i[units jobs].freeze

          # Declares the jobs with the block, then runs them.
          #
          # @param title [String] the headline above the jobs
          # @param concurrent [Boolean, Integer] see {Multi#run}
          # @param count [Symbol] what the headline bar counts: `:units`, the
          #   sum of every bar, or `:jobs`, how many jobs have ended
          # @param total [Integer, nil] the headline bar's total; nil for the
          #   sum of every bar's, or the number of jobs when counting jobs
          # @param stop [Stop, nil] see {Multi#run}
          # @yieldparam builder [Builder] declares the jobs
          # @return [Array<Object>] what each job returned, in declaration order
          # @raise [ArgumentError] with an invalid concurrent, count or total
          # @raise [Exception] the first error a job raised
          def run(title, concurrent: true, count: :units, total: nil, stop: nil, &)
            raise ArgumentError, "count must be one of #{COUNTS.inspect}, got #{count.inspect}" unless COUNTS.include?(count)

            Progress.total(total) unless total.nil?
            @count = count
            @total = total
            super(title, concurrent: concurrent, stop: stop, &)
          end

          private

          # @param job [Job]
          # @return [Boolean] whether the job was declared with `spinner`
          def spinner?(job) = job.handle.is_a?(Line)

          # @param job [Job]
          # @return [Object]
          def call(job) = spinner?(job) ? Line.call(job.work, job.handle) : super

          # @param job [Job]
          # @return [Boolean] whether its line or its bar was told to fail
          def reported_failure?(job) = job.handle.failed?

          # @param job [Job]
          # @return [Progress::Handle, nil] nil for a spinner, which has no progress
          def progress_of(job) = spinner?(job) ? nil : job.handle

          # @param job [Job]
          # @param width [Integer]
          # @return [String]
          def running(job, width)
            return [job.label, job.handle.detail].reject(&:empty?).join(" ") if spinner?(job)

            "#{job.label.ljust(width)} #{meter(job.handle.current, job.handle.total, job.started, job.handle.color)}"
          end

          # @param job [Job]
          # @return [String]
          def summary(job) = job.handle.summary(job.label)

          # @param width [Integer]
          # @return [String]
          def running_headline(width)
            "#{title.ljust(width)} #{meter(current, total, started)}"
          end

          # @return [String]
          def headline_summary = "#{title} #{current}/#{total}"

          # @return [Integer] units completed across every job, or jobs ended
          def current
            return jobs.count(&:seconds) if @count == :jobs

            bars.sum { |job| job.handle.current }
          end

          # @return [Integer] the total given; or units across every job,
          #   counting what a job without a total has done so far; or every job
          def total
            return @total if @total
            return jobs.size if @count == :jobs

            bars.sum { |job| job.handle.total || job.handle.current }
          end

          # @return [Array<Job>] the jobs that have a bar
          def bars = jobs.reject { spinner?(it) }

          # `[◼◼◼   ] 48%  96/200  ETA 3.1s`, with the count right-aligned to
          # the widest any row can show, so every count ends in one column.
          #
          # A bar whose total is not known yet is drawn empty, counting `12/?`.
          #
          # @param done [Integer]
          # @param all [Integer, nil]
          # @param since [Float, nil] when the work started, by the clock
          # @param color [Symbol, nil] the bar's own colour, if any
          # @return [String]
          def meter(done, all, since, color = nil)
            ratio = if all.nil? then 0.0
                    elsif all.zero? then 1.0
                    else done.fdiv(all)
                    end
            bar = Progress.bar(terminal.pastel, config, ratio, bar_columns, color: color)
            format("%<bar>s %<percent>3d%%  %<count>s  ETA %<eta>s",
                   bar: bar, percent: (ratio * 100).floor, count: "#{done}/#{all || '?'}".rjust(count_width), eta: eta(done, all, since))
          end

          # The widest count any row shows: the headline's, once every job is done.
          #
          # @return [Integer]
          def count_width = "#{total}/#{total}".length

          # One width for every bar, so the headline's lines up with the jobs'.
          #
          # @return [Integer]
          def bar_columns
            [terminal.width - label_width - 3 - Progress::CHROME, Progress::MIN_BAR].max
          end

          # @param done [Integer]
          # @param all [Integer, nil]
          # @param since [Float, nil]
          # @return [String] the time left at the rate so far, or `--` before
          #   any progress or while the total is not known
          def eta(done, all, since)
            return "--" if since.nil? || done.zero? || all.nil?

            Duration.format((clock.call - since) / done * (all - done))
          end
        end
      end
    end
  end
end
