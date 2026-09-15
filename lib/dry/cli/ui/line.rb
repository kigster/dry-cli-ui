# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # What a spinner or a task gives its block, so the work can report on
      # itself while it runs.
      #
      # `detail` is shown after the label while the work runs, and redrawn in
      # place on an animated terminal. Without animation it is kept and never
      # printed, since it may change many times a second.
      #
      # `fail` ends the work as a failure without raising: the outcome line
      # reads `✗ label: reason (1.2s)`, and the block's value is still
      # returned. Every method may be called from any thread.
      #
      # @example
      #   ui.spinner("Importing") do |line|
      #     rules.each { |rule| line.detail = rule.name }
      #     line.fail("3 rules skipped") if skipped.any?
      #   end
      class Line
        # @yieldparam detail [String] called whenever the detail changes, by
        #   the widget that draws the line
        def initialize(&on_change)
          @on_change = on_change
          @lock = Mutex.new
          @detail = ""
          @failed = false
          @reason = nil
        end

        # Calls a block with a line, or without one when the block is a
        # lambda that takes no arguments and would reject it.
        #
        # @param job [Proc]
        # @param line [Line]
        # @return [Object] whatever the block returns
        def self.call(job, line)
          job.lambda? && job.arity.zero? ? job.call : job.call(line)
        end

        # @return [String] the text shown after the label, empty for none
        def detail = lock.synchronize { @detail }

        # @param text [#to_s, nil] the text to show after the label; nil for none
        def detail=(text)
          text = text.to_s
          lock.synchronize { @detail = text }
          on_change&.call(text)
        end

        # Ends the work as a failure when the block returns, without raising.
        #
        # @param reason [#to_s, nil] shown after the label
        # @return [self]
        def fail(reason = nil)
          lock.synchronize do
            @failed = true
            @reason = reason&.to_s
          end
          self
        end

        # @return [Boolean] whether {#fail} was called
        def failed? = lock.synchronize { @failed }

        # @return [String, nil] what {#fail} was given
        def reason = lock.synchronize { @reason }

        # The label with the failure's reason after it, when there is one.
        #
        # @param label [String]
        # @return [String]
        def summary(label)
          text = reason
          failed? && !text.to_s.empty? ? "#{label}: #{text}" : label
        end

        private

        # @return [Proc, nil]
        attr_reader :on_change

        # @return [Mutex]
        attr_reader :lock
      end
    end
  end
end
