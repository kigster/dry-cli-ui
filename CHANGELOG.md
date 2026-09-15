## [Unreleased]

## [0.2.0]

- `ui.spinner` and every `ui.tasks` task give their block a `Dry::CLI::UI::Line`. `line.detail = "..."` shows text after the label while the work runs, redrawn in place on an animated terminal and never printed otherwise. `line.fail("reason")` ends the work as `✗ label: reason` without raising; the spinner still returns the block's value, and a task tree runs on past a task that fails this way.
- `concurrent:` on `ui.tasks` and `group` also takes a positive Integer, the most tasks that run at once. Anything other than `true`, `false` or a positive Integer raises `ArgumentError`.
- `ui.popup(*paragraphs, title:, width:)` draws a box on `err` over whatever is on the screen: sized to its text, centred, with the cursor left where it was. Without animation it is the same box `ui.box` draws.

## [0.1.0]

- Initial release of `dry-cli-ui`, which replaces `dry-cli-autocomplete` in this repository.
- `include Dry::CLI::UI` gives a command `ui`: `debug`, `info`, `success`, `warn`, `error` and `fatal` boxes, `box`, `status`, `spinner`, `progress`, `tasks` (nested and concurrent task trees), `table`, `prompt` and `confirm`.
- Plain-text fallback when a stream is not a terminal or runs under `TERM=dumb`; `NO_COLOR` support.
