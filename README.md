# dry-cli-ui

[![Ruby](https://github.com/kigster/dry-cli-ui/actions/workflows/main.yml/badge.svg)](https://github.com/kigster/dry-cli-ui/actions/workflows/main.yml) ![Coverage](docs/img/badge.svg)

Runtime terminal UI for [dry-cli](https://github.com/dry-rb/dry-cli) commands: spinners, progress bars, boxes, status lines, task trees, tables and prompts.

> [!NOTE]
> The design, and the reasons behind it, are in [SPECIFICATION](SPECIFICATION.md).

A long-running command has more to say than `puts` can show well: what it is doing now, how far along it is, what went wrong. Include one module and the command gets a `ui` that says it, in colour and in place on a terminal, and as plain lines when the output is piped to a file or a CI log.

## Installation

```ruby
gem "dry-cli-ui"
```

Requires Ruby 4.0 or later.

## Usage

```ruby
require "dry/cli"
require "dry-cli-ui"

class Import < Dry::CLI::Command
  include Dry::CLI::UI

  def call(**)
    ui.info "Importing tax rules..."

    rules = ui.spinner("Loading tax rules") { load_rules }

    ui.progress("Importing rules", total: rules.size) do |bar|
      rules.each do |rule|
        import(rule)
        bar.advance
      end
    end

    ui.success "Imported #{rules.size} rules"
  rescue => e
    ui.error("Import failed", e.message)
  end
end
```

When the output is piped, and the import fails part way:

```text
Loading tax rules...
✓ Loading tax rules (0.3s)
Importing rules...
✗ Importing rules 1482/1900 (4.1s)
┌─ Error ──────────────────────────────────────────────────┐
│                                                          │
│  Import failed                                           │
│                                                          │
│  Could not validate rule US.2026.IRC.199A: missing       │
│  dependency taxable_income                               │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

On a terminal the spinner turns and the bar fills in place, with percent, count and ETA, and each is replaced by the same `✓` or `✗` line when its block ends.

Include the module once in a base class and every command has `ui`. Including it loads nothing: the TTY gems load the first time `ui` is used.

## API

### Messages

```ruby
ui.debug   "Resolved 1900 rules from 14 files"
ui.info    "Importing tax rules..."
ui.success "Imported 1900 rules"
ui.warn    "3 rules have no effective date"
ui.error   "Import failed", e.message
ui.fatal   "Database unreachable"
```

Each draws a box with a single white border and the level's name as a coloured title. Every argument is a paragraph, wrapped to fit. The box fills the terminal less a two-column margin, or takes a fixed width:

```ruby
ui.info "Short and narrow", width: 40
ui.box "Name: Alan Turing", "Role: Cryptanalyst", title: "Profile"   # untitled without title:
```

### Popups

```ruby
ui.popup "h  help", "q  quit", title: "Keys"
```

On a terminal, a box drawn over whatever is on the screen: only as wide as its text, centred, and leaving the cursor where it was, so a spinner or a redrawn screen carries on underneath. Piped, it is the same box `ui.box` draws, on `err`.

### Status lines

```ruby
ui.status "Connected to the database", level: :success   # ✓ Connected to the database
ui.status "Disk nearly full", level: :warn               # ⚠ Disk nearly full
```

### Spinners

```ruby
rules = ui.spinner("Loading tax rules") { load_rules }
```

Returns the block's value. Leaves `✓ Loading tax rules (0.3s)` behind, or `✗` and the re-raised error when the block fails.

The block is given a `Dry::CLI::UI::Line`, for work that has more to say while it runs, or that can fail without raising:

```ruby
ui.spinner("Importing rules") do |line|
  rules.each { |rule| line.detail = rule.name; import(rule) }
  line.fail("#{skipped.size} rules skipped") if skipped.any?
end
```

`line.detail = "..."` shows text after the label, redrawn in place as it changes. Piped, the detail is kept and never printed, since it can change many times a second. `line.fail(reason)` ends the spinner as `✗ Importing rules: 3 rules skipped (4.1s)` without raising, and the block's value is still returned. `line.failed?` and `line.reason` read it back. Every `Line` method is safe to call from any thread.

### Progress bars

```ruby
ui.progress("Importing rules", total: rules.size) do |bar|
  rules.each do |rule|
    import(rule)
    bar.advance        # or bar.advance(10)
  end
end
```

The bar shows percent, `current/total` and ETA, and ends with `✓ Importing rules 1900/1900 (4.2s)`.

### Task trees

The block declares the tasks; they run once it returns, so the tree is drawn complete before the first one starts.

```ruby
ui.tasks("Deploy") do |t|
  t.task("Build assets") { build }
  t.group("Migrate") do |g|
    g.task("users") { migrate(:users) }
    g.task("orders") { migrate(:orders) }
  end
  t.group("Warm caches", concurrent: true) do |g|
    g.task("fonts") { warm(:fonts) }
    g.task("images") { warm(:images) }
  end
  t.task("Restart") { restart }
end
```

On a terminal, once it finishes:

```text
Deploy
├─ ✓ Build assets (0.4s)
├─ ✓ Migrate (0.3s)
│  ├─ ✓ users (0.1s)
│  └─ ✓ orders (0.2s)
├─ ✓ Warm caches (0.5s)
│  ├─ ✓ fonts (0.5s)
│  └─ ✓ images (0.3s)
└─ ✓ Restart (0.3s)
```

While it runs, the tree redraws in place and every running task has its own spinner. Piped, each line is printed once it is final, and a group's line appears as `▸` when it starts. `concurrent: true` runs a group's tasks at the same time, on a group or on `ui.tasks` itself, and `concurrent: 3` runs at most three at once. When a task raises, it is marked `✗`, tasks already running finish, the rest are marked skipped (`–`), and the error is re-raised.

Each task is given a `Line`, as a spinner's block is. Its detail is drawn after the task's name while it runs, and `line.fail(reason)` marks the task `✗ name: reason` and its groups `✗`, while the rest of the tree runs on:

```ruby
ui.tasks("Fetching", concurrent: 4) do |t|
  assets.each do |asset|
    t.task(asset.name) do |line|
      fetch(asset) { |percent| line.detail = "#{percent}%" }
    rescue Timeout::Error
      line.fail("timed out")
    end
  end
end
```

### Tables

```ruby
ui.table([["Alan Turing", 41], ["Ada Lovelace", 36]], header: %w[Name Age])
```

```text
┌──────────────┬─────┐
│ Name         │ Age │
├──────────────┼─────┤
│ Alan Turing  │ 41  │
│ Ada Lovelace │ 36  │
└──────────────┴─────┘
```

Tables are never truncated or rotated to fit the screen.

### Prompts

```ruby
name = ui.prompt("Name?", default: "Alan Turing")
env  = ui.prompt("Environment?", choices: %w[staging production], default: "staging")
tier = ui.prompt("Tier?", choices: { "Free" => :free, "Pro" => :pro })
ui.confirm("Deploy to #{env}?", default: false)
```

On a terminal these use arrow-key menus and line editing. Otherwise they read lines from standard input, so answers can be piped:

```bash
printf 'production\ny\n' | mycli deploy
```

When the input runs out, a prompt returns its default, or raises `Dry::CLI::UI::NonInteractiveError` if it has none.

## Where output goes

| To `out` (results)                                          | To `err` (everything else)                                                               |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `info`, `success`, `box`, `table`, `status` at those levels | `debug`, `warn`, `error`, `fatal`, `popup`, spinners, progress bars, task trees, prompts |

`mycli export > rules.csv` therefore writes only the command's results to the file, while its progress stays on the screen. `ui` writes to the streams dry-cli was called with, so `Dry::CLI.new(registry).call(out: io, err: io)` captures everything.

A stream that is not a terminal, or runs under `TERM=dumb`, gets no animation, no cursor movement and no escape codes. [`NO_COLOR`](https://no-color.org) turns colour off and leaves animation on.

## Configuration

Override `ui` to configure the console:

```ruby
class ApplicationCommand < Dry::CLI::Command
  include Dry::CLI::UI

  def ui
    @ui ||= Dry::CLI::UI::Console.new(
      out: out || $stdout,
      err: err || $stderr,
      box_width: 72,     # boxes are 72 columns rather than the whole terminal
      color: nil,        # true or false to override detection
      animate: nil       # true or false to override detection
    )
  end
end
```

## Relationship to dry-cli-help

`dry-cli-help` is static presentation: what does this command do? `dry-cli-ui` is runtime presentation: what is this command doing? Use either, or both.

```ruby
gem "dry-cli"
gem "dry-cli-help"
gem "dry-cli-ui"
```

## Development

```bash
bin/setup               # bundle install
just test               # the suite, with 100% line and branch coverage enforced
just lint               # rubocop
just ci                 # both
just format             # rubocop -a, then mdformat
bin/console             # IRB with the gem loaded
```

Specs render into a `StringIO`. The animated code paths run against `FakeTTY`, a `StringIO` that answers `tty?` with true, and elapsed times come from a fake clock.

## Contributing

Bug reports and pull requests are welcome at <https://github.com/kigster/dry-cli-ui>.

> [!WARNING]
> The `dry-` prefix and the `Dry::CLI::UI` namespace do not imply endorsement by `dry-rb`. This is an independent gem that extends theirs.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
