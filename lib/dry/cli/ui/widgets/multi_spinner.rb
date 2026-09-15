# frozen_string_literal: true

module Dry
  class CLI
    module UI
      module Widgets
        # Several spinners under one headline, one per job, all turning at once.
        #
        # Each job is given a {Line}: its detail is drawn after the label while
        # the job runs, on an animated terminal, and {Line#fail} ends it as
        # `✗ label: reason` without raising. The headline ends `✓` when every
        # job succeeded, and `✗` otherwise.
        #
        # @example
        #   ui.multi_spinner("Fetching", concurrent: 2) do |m|
        #     m.spinner("fonts") { fetch(:fonts) }
        #     m.spinner("images") { |line| fetch(:images) { |name| line.detail = name } }
        #   end
        #
        # See {Multi} for how the jobs run and how the rows are drawn.
        class MultiSpinner < Multi
          # What the declaration block is given.
          class Builder
            # @param jobs [Array<Multi::Job>] the list new jobs are appended to
            def initialize(jobs)
              @jobs = jobs
            end

            # Declares a job with a spinner of its own.
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

          private

          # @param job [Job]
          # @return [Object]
          def call(job) = Line.call(job.work, job.handle)

          # @param job [Job]
          # @return [Boolean]
          def reported_failure?(job) = job.handle.failed?

          # The label, then the detail when the job has one.
          #
          # @param job [Job]
          # @return [String]
          def running(job, _width)
            detail = job.handle.detail
            detail.empty? ? job.label : "#{job.label} #{detail}"
          end

          # @param job [Job]
          # @return [String] the label, with the reason once the job has failed
          def summary(job) = job.handle.summary(job.label)
        end
      end
    end
  end
end
