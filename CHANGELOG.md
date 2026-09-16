## [0.5.1]

- `ui.stoppable { |stop| ... }` makes Ctrl-C ask for a stop instead of interrupting, and `ui.multi_spinner` and `ui.multi_progress` take `stop:`. Once it is set, the jobs running finish, the rest are skipped, and the headline says `stopping`, then ends skipped. A second Ctrl-C interrupts. `Dry::CLI::UI::Stop` is the object behind it.
- `ui.multi_spinner` and `ui.multi_progress` stay animated when their rows do not fit on the screen. Only the running jobs are shown under the headline, as many as fit. Before, every row was printed one by one.
- `m.progress` inside `ui.multi_progress` takes `total: nil` for a job that learns its size as it runs. Its bar is empty and counts `12/?` until the job sets `bar.total =`, which every progress handle now has.
- `ui.multi_progress` takes `count: :jobs`, so the headline bar counts the jobs that ended, and `total:`, the headline's own total for bars that overlap.
- `examples/bin/mycli download-urls` sends each URL's `HEAD` request when its turn comes, not all of them first, and writes each file as its body arrives. `find-hosts --progress` gives its headline a total of the addresses scanned, not twice that. Both take `-c/--concurrency`, from 1 to 100, 10 by default, and on Ctrl-C finish what is running and report how many URLs were downloaded or addresses scanned.

## [0.5.0]

- The README documents every public method, option and error, with the plain output each widget prints when piped, and a section on testing a command with `StringIO`.
- `ui.progress` and `m.progress` inside `ui.multi_progress` take `color:`, a Pastel style for that bar's finished part in place of the configured `bar_color`, so bars side by side can differ. An unknown style raises `ArgumentError`.
- `bar_background` defaults to `nil`, so bars no longer sit on a gray track; the brackets mark where each bar begins and ends.
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
