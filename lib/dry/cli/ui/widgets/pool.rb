# frozen_string_literal: true

require "concurrent"

module Dry
  class CLI
    module UI
      module Widgets
        # Runs a list of items one at a time, all at once, or at most so many
        # at once, for every widget that runs several pieces of work.
        #
        # When one raises, items already running finish, items not yet
        # started are never started, and the first error is re-raised once
        # everything running has stopped. Once a {Stop} is set, items not yet
        # started are never started either.
        module Pool
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

          # Runs the block for each item.
          #
          # @param items [Array]
          # @param concurrent [Boolean, Integer] see {.concurrency}
          # @param stop [Stop, nil] checked before each item starts
          # @yieldparam item [Object] one of the items
          # @return [void]
          # @raise [Exception] the first error any block raised
          def self.run(items, concurrent, stop: nil, &each)
            return items.each { |item| stop&.stopped? ? break : each.call(item) } unless concurrent

            futures = concurrent == true ? all_at_once(items, &each) : at_most(concurrent, items, stop, &each)
            futures.each(&:wait)
            failed = futures.find(&:rejected?)
            raise failed.reason if failed
          end

          # @param items [Array]
          # @return [Array<Concurrent::Promises::Future>] one per item
          def self.all_at_once(items, &)
            items.map { |item| Concurrent::Promises.future(item, &) }
          end

          # Workers that take items off a queue until it is empty, or until
          # one of them raises.
          #
          # @param limit [Integer]
          # @param items [Array]
          # @param stop [Stop, nil]
          # @return [Array<Concurrent::Promises::Future>] one per worker
          def self.at_most(limit, items, stop, &)
            queue = Queue.new
            items.each { |item| queue << item }
            queue.close
            failed = Concurrent::AtomicBoolean.new
            Array.new([limit, items.size].min) { Concurrent::Promises.future { work(queue, failed, stop, &) } }
          end

          # @param queue [Queue] closed, so `pop` returns nil once it is empty
          # @param failed [Concurrent::AtomicBoolean] set once any worker raises
          # @param stop [Stop, nil]
          # @return [void]
          def self.work(queue, failed, stop, &each)
            ok = false
            while !stop&.stopped? && (item = queue.pop) && failed.false?
              each.call(item)
            end
            ok = true
          ensure
            failed.make_true unless ok
          end

          private_class_method :all_at_once, :at_most, :work
        end
      end
    end
  end
end
