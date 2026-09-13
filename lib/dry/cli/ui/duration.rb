# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # Measures and formats elapsed time.
      module Duration
        # The default clock: monotonic seconds, immune to wall-clock changes.
        CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

        # Formats a number of seconds for a human.
        #
        # @example
        #   Duration.format(0.42)  # => "0.4s"
        #   Duration.format(62)    # => "1m 02s"
        #   Duration.format(3720)  # => "1h 02m"
        #
        # @param seconds [Numeric]
        # @return [String]
        def self.format(seconds)
          case seconds
          in ...60 then Kernel.format("%<s>.1fs", s: seconds)
          in ...3600 then Kernel.format("%<m>dm %<s>02ds", m: seconds / 60, s: seconds % 60)
          else Kernel.format("%<h>dh %<m>02dm", h: seconds / 3600, m: (seconds % 3600) / 60)
          end
        end
      end
    end
  end
end
