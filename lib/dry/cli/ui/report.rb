# frozen_string_literal: true

require "delegate"

module Dry
  class CLI
    module UI
      # A file a command writes its report to, through `-o`. It behaves as the file it wraps, and
      # answers `color?` with true, so a {Terminal} on it writes colour although it is no TTY.
      class Report < ::SimpleDelegator
        # @return [Boolean] always true: a report is written in colour
        def color? = true
      end
    end
  end
end
