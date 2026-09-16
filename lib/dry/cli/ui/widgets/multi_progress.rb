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
        # @example
        #   ui.multi_progress("Downloading") do |m|
        #     files.each do |file|
        #       m.progress(file.name, total: file.size, color: file.large? ? :yellow : nil) do |bar|
        #         download(file) { |bytes| bar.advance(bytes) }
        #       end
        #     end
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
            # @param total [Integer] units of work
            # @param color [Symbol, nil] the finished part's Pastel style; nil for
            #   {Configuration#bar_color}
            # @yieldparam progress [Progress::Handle] call `advance` as units complete
            # @return [self]
            # @raise [ArgumentError] without a block, when total is not a
            #   non-negative Integer, or when color is not a Pastel style
            def progress(label, total:, color: nil, &work)
              raise ArgumentError, "progress #{label.inspect} needs a block" unless work
              raise ArgumentError, "total must be a non-negative Integer, got #{total.inspect}" unless total.is_a?(Integer) && total >= 0

              @jobs << Multi::Job.new(label, work, Progress::Handle.new(total, nil, color: Progress.color(color)))
              self
            end
          end

          private

          # @param job [Job]
          # @return [Progress::Handle]
          def progress_of(job) = job.handle

          # @param job [Job]
          # @param width [Integer]
          # @return [String]
          def running(job, width)
            "#{job.label.ljust(width)} #{meter(job.handle.current, job.handle.total, job.started, job.handle.color)}"
          end

          # @param job [Job]
          # @return [String]
          def summary(job) = "#{job.label} #{job.handle.current}/#{job.handle.total}"

          # @param width [Integer]
          # @return [String]
          def running_headline(width)
            "#{title.ljust(width)} #{meter(current, total, started)}"
          end

          # @return [String]
          def headline_summary = "#{title} #{current}/#{total}"

          # @return [Integer] units completed across every job
          def current = jobs.sum { |job| job.handle.current }

          # @return [Integer] units across every job
          def total = jobs.sum { |job| job.handle.total }

          # `[◼◼◼   ] 48%  96/200  ETA 3.1s`, with the count right-aligned to
          # the widest any row can show, so every count ends in one column.
          #
          # @param done [Integer]
          # @param all [Integer]
          # @param since [Float, nil] when the work started, by the clock
          # @param color [Symbol, nil] the bar's own colour, if any
          # @return [String]
          def meter(done, all, since, color = nil)
            ratio = all.zero? ? 1.0 : done.fdiv(all)
            bar = Progress.bar(terminal.pastel, config, ratio, bar_columns, color: color)
            format("%<bar>s %<percent>3d%%  %<count>s  ETA %<eta>s",
                   bar: bar, percent: (ratio * 100).floor, count: "#{done}/#{all}".rjust(count_width), eta: eta(done, all, since))
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
          # @param all [Integer]
          # @param since [Float, nil]
          # @return [String] the time left at the rate so far, or `--` before any progress
          def eta(done, all, since)
            return "--" if since.nil? || done.zero?

            Duration.format((clock.call - since) / done * (all - done))
          end
        end
      end
    end
  end
end
