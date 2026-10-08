# frozen_string_literal: true

# Whether the dry-cli under test gives a command public `stdout`, `stderr` and `stdin`
# (kigster/dry-cli#1 to #4). dry-cli 1.4 and earlier give it protected `out` and `err` instead.
DRY_CLI_PUBLIC_STREAMS = Dry::CLI::Command.public_method_defined?(:stdout)
