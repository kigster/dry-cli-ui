# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

A Ruby gem that gives `dry-cli` commands a runtime terminal UI. A command includes `Dry::CLI::UI` and calls `ui.info`, `ui.error`, `ui.spinner`, `ui.progress`, `ui.tasks`, `ui.table`, `ui.prompt` and the rest. On a terminal the output is coloured and animated; piped, it is plain lines.

**Read `SPECIFICATION.md` first.** It carries the API, the design decisions and the acceptance criteria. This file covers how to work in the repository.

This repository used to be `dry-cli-autocomplete`. Nothing of that gem remains; its history is in git.

## Environment

Ruby 4.0.6 via rbenv (`.ruby-version`). Prefix every Ruby command:

```bash
eval "$(rbenv init -)" && bundle exec rspec
```

```bash
bundle install
just test                      # the suite; enforces 100% line and branch coverage
just lint                      # rubocop
just ci                        # both
bundle exec rake               # the specs, as CI runs them (with COVERAGE=true)
bin/console                    # IRB with the gem loaded
```

The gemspec sets `required_ruby_version >= 4.0` and `.rubocop.yml` sets `TargetRubyVersion: 4.0`. Keep the two in step.

## The trap

**dry-cli declares `Dry::CLI`, and it is a class, not a module.** Reopening a class as a module raises `TypeError` the moment both are loaded. Nest every file as:

```ruby
module Dry
  class CLI          # class, and CLI is an acronym
    module UI
```

`lib/dry/cli/ui/version.rb` deliberately does not `require "dry/cli"`, because the gemspec loads it at build time. It reopens `class CLI` on its own, which is compatible whichever loads first.

Inside `module Dry`, a bare `Struct` resolves to `Dry::Struct` in any host that loads dry-struct. Value objects here are `::Data.define`, written with the leading `::`.

## Architecture

| File                          | Role                                                                            |
| ----------------------------- | ------------------------------------------------------------------------------- |
| `lib/dry/cli/ui.rb`           | The mixin: defines `#ui`, autoloads everything else.                            |
| `lib/dry/cli/ui/console.rb`   | The public API. Picks a widget and a stream for each call.                      |
| `lib/dry/cli/ui/terminal.rb`  | One stream: whether it is a TTY, may animate, may colour; its width and height. |
| `lib/dry/cli/ui/theme.rb`     | Levels (title, glyph, colour, stream) and operation states.                     |
| `lib/dry/cli/ui/duration.rb`  | Monotonic clock and elapsed-time formatting.                                    |
| `lib/dry/cli/ui/widgets/*.rb` | One renderer per widget, each with its rich form and its plain fallback.        |

Rules that hold this together:

- **Including the module loads nothing.** Everything past the mixin is `autoload`ed. `spec/dry/cli/ui_spec.rb` checks `$LOADED_FEATURES` in a fresh process; keep it passing.
- **No TTY object crosses the public API.** `Console` methods neither return nor yield one. `ui.progress` yields `Widgets::Progress::Handle`, not a `TTY::ProgressBar`.
- **Widgets decide rich versus plain by asking their `Terminal`**, never by inspecting an IO. Fallback lives in one place.
- **Results go to `out`, everything else to `err`.** The mapping is in `Theme::LEVELS` and `Console`.
- **Inject, do not stub globals.** Widgets take a `Terminal` and a `clock:`; specs pass a `StringIO`, a `FakeTTY` and a `FakeClock` from `spec/support/fakes.rb`.

## Conventions

- **Coverage is 100% line and 100% branch, and the suite fails below it.** A focused run (`rspec spec/some_spec.rb`) skips the check unless `COVERAGE` is set.
- **YARD on every class, module, method and attribute.** `bundle exec yard stats --list-undoc` is the check.
- **Specs**: `let`, `subject`, `rspec-its` one-liners; assert on what a user reads (`plain(output)` strips ANSI), and on escape sequences only where they are the point.
- **Commit messages**: imperative mood, 50-character subject, no full stop.
- **Writing prose here**: no em dashes, active voice, plain words. Say what a thing does.

## Repository layout

| Path                        | What it is                                       |
| --------------------------- | ------------------------------------------------ |
| `SPECIFICATION.md`          | What the gem does, why, and what "done" means    |
| `lib/dry-cli-ui.rb`         | Entry point matching the gem name                |
| `lib/dry/cli/ui/version.rb` | Version, loaded standalone by the gemspec        |
| `sig/dry/cli/ui.rbs`        | RBS signatures for the public API                |
| `spec/support/fakes.rb`     | `FakeTTY`, `FakeClock`, `MinimalIO`, `plain`     |
| `.github/workflows/`        | CI: specs with coverage and a gem build; rubocop |
| `justfile`, `lefthook.yml`  | Local recipes and pre-commit hooks               |
