# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # A request to stop starting new work, which any thread may make or
      # check. The multi widgets take one as `stop:`: once it is set, jobs
      # already running finish, and jobs not yet started are skipped.
      #
      # {#trap} sets it on Ctrl-C, so a command can end early and still report
      # what it did. A second Ctrl-C interrupts as usual.
      #
      # @example
      #   ui.stoppable do |stop|
      #     files = ui.multi_spinner("Downloading", concurrent: 10, stop: stop) { |m| ... }
      #     ui.info "Stopped after #{files.compact.size} files" if stop.stopped?
      #   end
      class Stop
        # A plain flag rather than an atomic one, which takes a lock, and a
        # trap handler may not. Setting it once, to true, is safe to race.
        def initialize
          @stopped = false
        end

        # @return [Boolean] whether a stop was asked for
        def stopped? = @stopped

        # Asks for a stop.
        #
        # @return [self]
        def stop!
          @stopped = true
          self
        end

        # Runs the block with the signal trapped: the first one asks for a
        # stop, and the next raises `Interrupt`. The previous handler is put
        # back when the block ends.
        #
        # @param signal [String]
        # @yieldparam stop [Stop] this stop
        # @return [Object] whatever the block returns
        def trap(signal = "INT")
          previous = Signal.trap(signal) { stopped? ? raise(Interrupt) : stop! }
          yield self
        ensure
          Signal.trap(signal, previous || "DEFAULT")
        end
      end
    end
  end
end
