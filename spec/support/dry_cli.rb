# frozen_string_literal: true

# Whether the dry-cli under test gives a command public `stdout`, `stderr` and `stdin`
# (kigster/dry-cli#1 to #4). dry-cli 1.4 and earlier give it protected `out` and `err` instead.
DRY_CLI_PUBLIC_STREAMS = Dry::CLI::Command.public_method_defined?(:stdout)

# Runs a CLI with its output going to the given streams, through whichever keywords the dry-cli
# under test takes.
module DryCliHelpers
  def call_cli(cli, arguments, out:, err:)
    streams = DRY_CLI_PUBLIC_STREAMS ? { stdout: out, stderr: err } : { out: out, err: err }
    cli.call(arguments: arguments, **streams)
  end
end

RSpec.configure { |config| config.include DryCliHelpers }
