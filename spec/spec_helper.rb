# frozen_string_literal: true

ENV["RUBYOPT"] = "-W0"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rspec/its"
require "stringio"
require "timeout"

# Coverage runs for the whole suite (`rspec` with no arguments) or whenever
# COVERAGE is set, which is how `rake` and CI run it. A focused run of one file
# would otherwise fail the minimum.
if ARGV.empty? || ENV["COVERAGE"]
  require "simplecov"
  require "coverage/badge"

  SimpleCov.start do
    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
    cover "lib/**/*.rb"
    self.formatters = SimpleCov::Formatter::MultiFormatter.new(
      [
        SimpleCov::Formatter::HTMLFormatter,
        Coverage::Badge::Formatter
      ]
    )
  end

  # Bundler reads the gemspec, and so this file, before coverage starts.
  verbose = $VERBOSE
  $VERBOSE = nil
  load File.expand_path("../lib/dry/cli/ui/version.rb", __dir__)
  $VERBOSE = verbose

  SimpleCov.at_exit do
    SimpleCov.result.format!
    puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
    FileUtils.mkdir_p("docs/img")
    FileUtils.mv("coverage/badge.svg", "docs/img/badge.svg")
  end
end

require "dry/cli"
require "dry-cli-ui"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

PROJECT_ROOT = File.expand_path("..", __dir__)

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.around do |example|
    Timeout.timeout(10) { example.run }
  end
end
