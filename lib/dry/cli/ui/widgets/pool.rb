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
        # everything running has stopped.
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
          # @yieldparam item [Object] one of the items
          # @return [void]
          # @raise [Exception] the first error any block raised
          def self.run(items, concurrent, &)
            return items.each(&) unless concurrent

            futures = concurrent == true ? all_at_once(items, &) : at_most(concurrent, items, &)
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
          # @return [Array<Concurrent::Promises::Future>] one per worker
          def self.at_most(limit, items, &)
            queue = Queue.new
            items.each { |item| queue << item }
            queue.close
            stop = Concurrent::AtomicBoolean.new
            Array.new([limit, items.size].min) { Concurrent::Promises.future { work(queue, stop, &) } }
          end

          # @param queue [Queue] closed, so `pop` returns nil once it is empty
          # @param stop [Concurrent::AtomicBoolean] set once any worker raises
          # @return [void]
          def self.work(queue, stop, &each)
            ok = false
            while (item = queue.pop) && stop.false?
              each.call(item)
            end
            ok = true
          ensure
            stop.make_true unless ok
          end

          private_class_method :all_at_once, :at_most, :work
        end
      end
    end
  end
end
