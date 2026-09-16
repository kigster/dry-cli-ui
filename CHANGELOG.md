## [Unreleased]

## [0.5.0]

- The README documents every public method, option and error, with the plain output each widget prints when piped, and a section on testing a command with `StringIO`.
- `SPECIFICATION.md` moves to `docs/SPECIFICATION.md`, marked as the specification for version 0.1.0, and is no longer part of the YARD documentation.

## [0.4.0]

- `ui.multi_spinner(title, concurrent: true)` runs several jobs at once, each under a spinner of its own, beneath a headline spinner. `ui.multi_progress(title, concurrent: true)` does the same with a progress bar per job and a headline bar that counts them all. The block declares the jobs with `m.spinner(label)` or `m.progress(label, total:)`; they run once it returns, all at once or at most `concurrent:` at a time, and the call returns what each job returned. Waiting jobs show `[ ]`, a job that raises is marked `[𝘅]`, jobs not yet started are skipped, and the first error is re-raised.
- Task trees and the multi widgets mark every row in brackets: `[ ]` while it waits and a turning `[⠏]` while it runs, both bold yellow, then a green `[✓]`, a red `[𝘅]`, or a yellow `[—]` for work that was skipped. Outcome lines use the same glyphs, so a failed spinner now ends `𝘅 Loading (0.5s)`.
- `Dry::CLI::UI.configure` sets `spinner_format` (a TTY::Spinner format name, or `{ interval:, frames: }`), `bar_format` (a TTY::ProgressBar bar format name, or `{ complete:, incomplete: }`), `bar_color` and `bar_background` (Pastel styles, or nil) for every spinner and bar. Spinners default to `:dots`. Bars now draw a green `◼` for each finished part on a gray track, between brackets, rather than `███░░░`. `Console.new` takes `config:` for a configuration of its own.
- `ui.status_bar(title, hints:)` keeps a status line at the bottom of the screen while its block runs: what started last, how many things are running, done and failed, overall progress, elapsed time and hints. Every widget inside the block reports to it. It sets no scroll region, so scrollback stays intact, and does nothing when `err` is not animated.
- `ui.multi_progress` right-aligns every count, so `8/503` and `1/8` end in the same column.

## [0.3.1]

- Adds `examples/`, a small dry-cli application (`bin/mycli`) that shows spinners and progress bars fetching URLs and computing primes.

## [0.3.0]

- `ui.spinner` and every `ui.tasks` task give their block a `Dry::CLI::UI::Line`. `line.detail = "..."` shows text after the label while the work runs, redrawn in place on an animated terminal and never printed otherwise. `line.fail("reason")` ends the work as `✗ label: reason` without raising; the spinner still returns the block's value, and a task tree runs on past a task that fails this way.
- `concurrent:` on `ui.tasks` and `group` also takes a positive Integer, the most tasks that run at once. Anything other than `true`, `false` or a positive Integer raises `ArgumentError`.
- `ui.popup(*paragraphs, title:, width:)` draws a box on `err` over whatever is on the screen: sized to its text, centred, with the cursor left where it was. Without animation it is the same box `ui.box` draws.

## [0.1.0]

- Initial release of `dry-cli-ui`, which replaces `dry-cli-autocomplete` in this repository.
- `include Dry::CLI::UI` gives a command `ui`: `debug`, `info`, `success`, `warn`, `error` and `fatal` boxes, `box`, `status`, `spinner`, `progress`, `tasks` (nested and concurrent task trees), `table`, `prompt` and `confirm`.
- Plain-text fallback when a stream is not a terminal or runs under `TERM=dumb`; `NO_COLOR` support.
