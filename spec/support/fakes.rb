# frozen_string_literal: true

# A StringIO that claims to be a terminal, so the animated code paths run and
# their output can be read back.
class FakeTTY < StringIO
  def tty? = true
end

# An output that has `print` and nothing else: no `tty?`, no `flush`.
class MinimalIO
  attr_reader :written

  def initialize
    @written = []
  end

  def print(text)
    written << text
  end
end

# A clock that advances by a fixed step every time it is read, so elapsed
# times in output are predictable.
class FakeClock
  def initialize(step = 0.5)
    @step = step
    @now = 0.0
  end

  def call
    @now += @step
  end
end

# Strips ANSI escape sequences, for asserting on what a user reads.
module AnsiHelpers
  def plain(text)
    text.gsub(/\e\[[\d;?]*[A-Za-z]/, "")
  end
end

RSpec.configure { |config| config.include AnsiHelpers }

RSpec::Matchers.define_negated_matcher :exclude, :include
