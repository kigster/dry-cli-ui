# Decisions on CLI conventions

Decided with the owner on 2026-10-08. The rule itself lives in the global agent instructions (`~/.agents/config/AGENTS.md`, section "CLI commands"); this file records what was decided for dry-cli-ui, why, and the order of the work.

## Decisions

| #   | Question                              | Decision                                                                                                                                                                                                        |
| --- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | Default to a dry run, with `--apply`? | Never. A command does its work when run. `-n/--dry-run` is added where a human would want to try it first. `--apply`, `--commit` and the like are removed.                                                      |
| D2  | Dangerous commands                    | May confirm with tty-prompt, YES/NO as a select list. `-y/--yes` skips every prompt.                                                                                                                            |
| D3  | Where the conventions live in Ruby    | In dry-cli-ui, not a separate gem. dry-cli-ui gains SemanticLogger and binding_of_caller as dependencies.                                                                                                       |
| D4  | Reserved short flags                  | `-n` dry run, `-y` yes, `-o` output, `-l` log, `-L` log level, the same in every CLI. An option that already uses one loses its short flag and keeps its long form. law-cli's `-y` for years becomes `--years`. |
| D5  | `-o/--output [FILE]` default          | `log/<executable>-<action>.<YYYY-MM-DD>.<HHMMSS>.log`, stamped with the time the process started. `-o -` is STDOUT. The file ends with the time it was closed.                                                  |
| D6  | `-l/--log [FILE]` default             | `log/<executable>-<action>.log`, no date (SemanticLogger stamps each line). `-l -` is STDOUT.                                                                                                                   |
| D7  | `-L/--log-level`, `--log-format`      | Levels `debug info warn error fatal`. Formats: whatever SemanticLogger supports, at least `standard` (the default, one line per entry) and `json`.                                                              |
| D8  | better_errors                         | Not used: it is Rack middleware and does nothing in a CLI. binding_of_caller records each frame's local variables beside a logged exception's backtrace.                                                        |
| D9  | Sequence                              | dry-cli-ui (two PRs: segmented bars; flags, output and logging), release, then law-cli, then the Rust `tc`.                                                                                                     |

## Decided without the owner (implementation detail, open to change)

- **A bare `-o` or `-l`.** dry-cli 1.4 gives every string option a required `VALUE`, so a bare `-o` fails to parse. Rather than wait on another upstream dry-cli change, dry-cli-ui rewrites a bare `-o`, `--output`, `-l` or `--log` (last on the line, or followed by another flag other than `-`) into an empty value before dry-cli parses. An empty value means "the default name". Like OptionParser's optional arguments, `-o word` takes `word` as the file.
- **Local variables only at debug.** Capturing every frame's bindings on every raise costs time, so binding_of_caller is switched on (a `TracePoint` on `:raise`) only when the log level is `debug`.
- **`log/` and `.gitignore`.** At runtime the gem creates `log/` at the repository root (the nearest directory up from the current one holding `.git`, else the current directory). It does not edit `.gitignore`; adding `/log/*` is a one-time step in each repository adopting the flags.
- **Bar segments order.** Red, then yellow, then green, left to right, in proportion to the items that ended each way; the rest of the bar is unfilled.
