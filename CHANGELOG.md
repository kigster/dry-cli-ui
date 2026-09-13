## [Unreleased]

## [0.1.0]

- Initial release of `dry-cli-ui`, which replaces `dry-cli-autocomplete` in this repository.
- `include Dry::CLI::UI` gives a command `ui`: `debug`, `info`, `success`, `warn`, `error` and `fatal` boxes, `box`, `status`, `spinner`, `progress`, `tasks` (nested and concurrent task trees), `table`, `prompt` and `confirm`.
- Plain-text fallback when a stream is not a terminal or runs under `TERM=dumb`; `NO_COLOR` support.
