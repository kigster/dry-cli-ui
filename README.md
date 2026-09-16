# dry-cli-ui

[![Ruby](https://github.com/kigster/dry-cli-ui/actions/workflows/main.yml/badge.svg)](https://github.com/kigster/dry-cli-ui/actions/workflows/main.yml) ![Coverage](docs/img/badge.svg)

Runtime terminal UI for [dry-cli](https://github.com/dry-rb/dry-cli) commands: spinners, progress bars, boxes, status lines, task trees, tables and prompts.

> [!NOTE]
> The design, and the reasons behind it, are in [SPECIFICATION](docs/SPECIFICATION.md).

A long-running command has more to say than `puts` can show well: what it is doing now, how far along it is, what went wrong. Include one module and the command gets a `ui` that says it, in colour and in place on a terminal, and as plain lines when the output is piped to a file or a CI log.

## Installation

```ruby
gem "dry-cli-ui"
```

Requires Ruby 4.0 or later and `dry-cli` 1.0 or later. The rendering comes from the [TTY toolkit](https://ttytoolkit.org) (`tty-box`, `tty-spinner`, `tty-progressbar`, `tty-table`, `tty-prompt`, `tty-cursor`, `tty-screen`), `pastel`, `strings` and `concurrent-ruby`, which Bundler installs with the gem.

Either require works, and both load the same file:

```ruby
require "dry-cli-ui"   # matches the gem name
require "dry/cli/ui"   # matches the constant Dry::CLI::UI
```

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
𝘅 Importing rules 1482/1900 (4.1s)
┌─ Error ────────────────────────────────────────────────────────────────────┐
│                                                                            │
│  Import failed                                                             │
│                                                                            │
│  Could not validate rule US.2026.IRC.199A: missing dependency              │
│  taxable_income                                                            │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

A stream that is not a terminal is taken to be 80 columns wide, so a piped box is 78.

On a terminal the spinner turns and the bar fills in place, with percent, count and ETA, and each is replaced by the same `✓` or `𝘅` line when its block ends.

Include the module once in a base class and every command has `ui`. Including it loads nothing: the TTY gems load the first time `ui` is used.

```ruby
class ApplicationCommand < Dry::CLI::Command
  include Dry::CLI::UI
end

class Import < ApplicationCommand
  def call(**) = ui.success("Nothing to import")
end
```

`ui` writes to the command's `out` and `err` when dry-cli has set them, and to `$stdout` and `$stderr` otherwise.

### Without dry-cli

`Dry::CLI::UI::Console` needs nothing from dry-cli, so a Rake task or a plain script can use it directly:

```ruby
require "dry-cli-ui"

ui = Dry::CLI::UI::Console.new
ui.spinner("Compacting the database") { compact! }
ui.success "Done"
```

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

Each draws a box with a single white border and the level's name as a coloured title, and returns `nil`. Every argument is a paragraph, wrapped to fit, with a blank line between paragraphs. The box fills the terminal less a two-column margin, or takes a fixed width:

```ruby
ui.info "Short and narrow", width: 40
```

```text
┌─ Info ───────────────────────────────┐
│                                      │
│  Short and narrow                    │
│                                      │
└──────────────────────────────────────┘
```

A `width:` is never wider than the terminal less its margin, and never narrower than 20 columns.

| Method    | Title   | Colour  | Stream |
| --------- | ------- | ------- | ------ |
| `debug`   | Debug   | gray    | `err`  |
| `info`    | Info    | cyan    | `out`  |
| `success` | Success | green   | `out`  |
| `warn`    | Warning | yellow  | `err`  |
| `error`   | Error   | red     | `err`  |
| `fatal`   | Fatal   | magenta | `err`  |

`ui.box` is the general form. Without `level:` it is untitled unless given a `title:`, uncoloured, and goes to `out`:

```ruby
ui.box "Name: Alan Turing", "Role: Cryptanalyst", title: "Profile", width: 40
```

```text
┌─ Profile ────────────────────────────┐
│                                      │
│  Name: Alan Turing                   │
│                                      │
│  Role: Cryptanalyst                  │
│                                      │
└──────────────────────────────────────┘
```

With `level:` it takes that level's colour and stream, and its title unless `title:` replaces it:

```ruby
ui.box "Disk is 91% full", level: :warn, title: "Disk"   # a yellow "Disk" box on err
ui.box "Plain and untitled"                              # no title, on out
```

An unknown level raises `ArgumentError`.

### Popups

```ruby
ui.popup "h  help", "q  quit", title: "Keys"
```

On a terminal, a box drawn over whatever is on the screen: only as wide as its text (at least 20 columns, at most `width:` or the box width), centred, and leaving the cursor where it was, so a spinner or a redrawn screen carries on underneath. Piped, it is the same box `ui.box` draws, on `err`:

```text
┌─ Keys ─────────────────────┐
│                            │
│  h  help                   │
│                            │
│  q  quit                   │
│                            │
└────────────────────────────┘
```

### Status lines

One line with a coloured glyph, on the level's stream. The level defaults to `:info`, and every argument is joined with a space:

```ruby
ui.status "Connected to the database", level: :success   # ✓ Connected to the database
ui.status "Disk nearly full", level: :warn               # ⚠ Disk nearly full
ui.status "Loaded", rules.size, "rules"                  # ℹ Loaded 1900 rules
```

| Level      | Glyph | Stream |
| ---------- | ----- | ------ |
| `:debug`   | `·`   | `err`  |
| `:info`    | `ℹ`   | `out`  |
| `:success` | `✓`   | `out`  |
| `:warn`    | `⚠`   | `err`  |
| `:error`   | `✗`   | `err`  |
| `:fatal`   | `✖`   | `err`  |

### Spinners

```ruby
rules = ui.spinner("Loading tax rules") { load_rules }
```

Returns the block's value. Leaves `✓ Loading tax rules (0.3s)` behind, or `𝘅` and the re-raised error when the block fails.

The block is given a `Dry::CLI::UI::Line`, for work that has more to say while it runs, or that can fail without raising:

```ruby
ui.spinner("Importing rules") do |line|
  rules.each { |rule| line.detail = rule.name; import(rule) }
  line.fail("#{skipped.size} rules skipped") if skipped.any?
end
```

`line.detail = "..."` shows text after the label, redrawn in place as it changes. Piped, the detail is kept and never printed, since it can change many times a second. `line.fail(reason)` ends the spinner as `𝘅 Importing rules: 3 rules skipped (4.1s)` without raising, and the block's value is still returned. `line.failed?`, `line.reason` and `line.detail` read it back. Every `Line` method is safe to call from any thread.

Piped, each of these prints its label with `...` when it starts, then its outcome:

```text
Loading tax rules...
✓ Loading tax rules (0.3s)
Importing rules...
𝘅 Importing rules: 3 rules skipped (4.1s)
```

A block that raises leaves `𝘅 Loading tax rules (0.3s)` and the error propagates, so `rescue` it around the call. A lambda that takes no arguments is called without a `Line`, so a method object or a stored lambda can be passed as it is:

```ruby
load = -> { YAML.load_file("rules.yml") }
rules = ui.spinner("Loading tax rules", &load)
```

Without a block, `spinner` raises `ArgumentError`. The same is true of `progress`, `multi_spinner`, `multi_progress`, `tasks` and `status_bar`.

Elapsed times read `0.4s` under a minute, `1m 02s` under an hour, and `1h 02m` after that.

### Progress bars

```ruby
ui.progress("Importing rules", total: rules.size) do |bar|
  rules.each do |rule|
    import(rule)
    bar.advance        # or bar.advance(10)
  end
end
```

The bar shows percent, `current/total` and ETA, `Importing rules [◼◼◼◼◼◼    ] 61%  1159/1900  ETA 2.7s`, and ends with `✓ Importing rules 1900/1900 (4.2s)`. On a terminal the `◼`s are green and the whole bar sits on a gray background; see [Configuration](#configuration) to change either.

The block is given a `Dry::CLI::UI::Widgets::Progress::Handle`, never the underlying `TTY::ProgressBar`:

```ruby
ui.progress("Copying", total: files.sum(&:size)) do |bar|
  files.each do |file|
    copy(file) { |bytes| bar.advance(bytes) }
    ui.status "#{bar.current} of #{bar.total} bytes" if bar.current == bar.total
  end
  :copied                                        # progress returns the block's value
end
```

- `advance(step = 1)` adds to `current` and returns the handle; `current` never passes `total`.
- `total:` must be a non-negative Integer, or `progress` raises `ArgumentError`.
- `total: 0` draws no bar, and ends `✓ Copying 0/0`.
- The outcome is `✓` whenever the block returns, even short of the total (`✓ Copying 12/20`), and `𝘅` when it raises.

Piped, it prints `Importing rules...` when it starts and the outcome line when it ends, with no bar in between.

### Several spinners at once

```ruby
ui.multi_spinner("Fetching", concurrent: 2) do |m|
  m.spinner("fonts") { fetch(:fonts) }
  m.spinner("images") do |line|
    fetch(:images) { |done, all| line.detail = "#{done} of #{all}" }
  end
  m.spinner("video") { fetch(:video) }
end
```

The block declares the jobs; they run once it returns, all at once by default, or at most `concurrent: 2` at a time. It returns what each job returned, in declaration order. While they run, every job has a row of its own under a headline spinner, and a job still waiting shows `[ ]`:

```text
[⠹] Fetching
├─ [⠹] fonts
├─ [⠹] images 12 of 40
└─ [ ] video
```

Once they finish, the headline ends `✓`, or `𝘅` when any job failed:

```text
[𝘅] Fetching (0.5s)
├─ [✓] fonts (0.3s)
├─ [𝘅] images: 2 timed out (0.3s)
└─ [✓] video (0.2s)
```

Each job is given a `Line`, as a single spinner's block is. When a job raises, jobs already running finish, jobs not yet started are marked skipped (`[—]`), and the first error is re-raised. A job that never ran has `nil` in the returned array, which matters only when you rescue the error.

`concurrent:` takes `true` (all at once, the default), `false` (one at a time, in order), or a positive Integer. Anything else, `0` included, raises `ArgumentError` before any job runs.

Piped, it prints `Fetching...`, then each job's outcome as it ends, then the headline's:

```text
Fetching...
  [✓] fonts (0.3s)
  [𝘅] images: 2 timed out (0.3s)
  [✓] video (0.2s)
𝘅 Fetching (0.5s)
```

When a job raises under `concurrent: 1`:

```text
Fetching...
  [𝘅] fonts (0.1s)
  [—] images
  [—] video
𝘅 Fetching (0.1s)
```

The rows are also printed one by one on a terminal that has fewer rows than the widget needs, since the cursor cannot move above the top of the screen.

### Several progress bars at once

```ruby
ui.multi_progress("Downloading") do |m|
  files.each do |file|
    m.progress(file.name, total: file.size) do |bar|
      download(file) { |bytes| bar.advance(bytes) }
    end
  end
end
```

The same shape as `multi_spinner`, with a bar per job and a headline bar that counts them all. Bars start and end in the same columns, and counts are right-aligned:

```text
[⠋] Downloading      [◼◼◼◼             ]  27%   66/240  ETA 2.1s
├─ [⠋] fonts.zip     [◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼ ]  95%    38/40  ETA 0.1s
├─ [⠋] images.tar.gz [◼◼◼              ]  23%   28/120  ETA 2.4s
└─ [ ] video.mp4
```

Each job is given the same handle as `ui.progress`, with `advance(step = 1)`, `current` and `total`. A finished job's row reads `[✓] fonts.zip 40/40 (0.1s)`, and the headline's `[✓] Downloading 240/240 (0.3s)`. It returns what each job returned, in declaration order, and takes `concurrent:` as `multi_spinner` does. Every `m.progress` needs a block and a non-negative Integer `total:`, or raises `ArgumentError`.

Piped:

```text
Downloading...
  [✓] fonts.zip 40/40 (0.1s)
  [✓] images.tar.gz 120/120 (0.2s)
  [✓] video.mp4 80/80 (0.3s)
✓ Downloading 240/240 (0.3s)
```

### Example: fetching many URLs

With `multi_spinner`, each URL gets a spinner, and the call returns every page in the same order as `urls`. Nothing writes to a shared file from several threads:

```ruby
bodies = ui.multi_spinner("Fetching #{urls.size} URLs", concurrent: 8) do |m|
  urls.each { |url| m.spinner(url) { fetch(url) } }
end

File.write("urls.txt", bodies.join("\n"))
```

With `multi_progress`, each URL gets a bar that fills one byte at a time as the body arrives. A bar's `total` is fixed when it is declared, so a `HEAD` request asks each URL for its size first:

```ruby
found = urls.filter_map do |url|
  [url, content_length(url)]
rescue StandardError => e
  ui.status "#{url}: #{e.message}", level: :warn
  nil
end

bodies = ui.multi_progress("Fetching #{found.size} URLs", concurrent: 8) do |m|
  found.each do |url, size|
    m.progress(url, total: size || 1) do |bar|
      body = download(url) { |bytes| bytes.times { bar.advance } if size }
      bar.advance unless size # no Content-Length: done in one step
      body
    end
  end
end

File.write("urls.txt", bodies.join("\n"))
```

The two helpers, with `Net::HTTP`:

```ruby
require "net/http"

def content_length(url)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.head(uri.request_uri).content_length # nil when the server does not say
  end
end

def download(url)
  uri = URI(url)
  body = +""
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request_get(uri.request_uri) do |response|
      response.read_body do |chunk|
        body << chunk
        yield chunk.bytesize
      end
    end
  end
  body
end
```

In both, at most eight requests run at once and the rest wait as `[ ]` rows. The headline counts every URL, and in `multi_progress` every byte. A server that sends no `Content-Length` gets a bar of one unit, which sits at 0% and fills when its download ends. These helpers are kept short: a real one follows redirects, and sends `Accept-Encoding: identity` so the bytes counted match `Content-Length`. With more URLs than the screen has rows, each finished URL prints one line instead.

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
├─ [✓] Build assets (0.4s)
├─ [✓] Migrate (0.3s)
│  ├─ [✓] users (0.1s)
│  └─ [✓] orders (0.2s)
├─ [✓] Warm caches (0.5s)
│  ├─ [✓] fonts (0.5s)
│  └─ [✓] images (0.3s)
└─ [✓] Restart (0.3s)
```

While it runs, the tree redraws in place and every running task has its own spinner. Every row is marked in brackets, in bold yellow while it waits, `[ ]`, and while it runs, a turning `[⠏]`; then a green `[✓]` when it is done, a red `[𝘅]` when it failed, or a yellow `[—]` when it was skipped. Piped, each line is printed once it is final, and a group's line appears as `[▸]` when it starts. `concurrent: true` runs a group's tasks at the same time, on a group or on `ui.tasks` itself, and `concurrent: 3` runs at most three at once. Without it, tasks run one after another. When a task raises, it is marked `[𝘅]`, tasks already running finish, the rest are marked skipped (`[—]`), and the error is re-raised. `ui.tasks` returns `nil`, and its title is optional: `ui.tasks { |t| ... }` draws the tree without a heading.

Piped, the same tree as the example above, with one migration failing:

```text
Deploy
├─ [✓] Build assets (0.4s)
├─ [▸] Migrate
│  ├─ [✓] users (0.1s)
│  └─ [𝘅] orders: table locked (0.2s)
├─ [▸] Warm caches
│  ├─ [✓] fonts (0.5s)
│  └─ [✓] images (0.3s)
└─ [✓] Restart (0.3s)
```

And when `Build assets` raises instead:

```text
Deploy
├─ [𝘅] Build assets (0.4s)
├─ [—] Migrate
│  ├─ [—] users
│  └─ [—] orders
├─ [—] Warm caches
│  ├─ [—] fonts
│  └─ [—] images
└─ [—] Restart
```

`task` and `group` each need a block, and `concurrent:` takes the same values as on the multi widgets; either mistake raises `ArgumentError` while the tree is being declared, before anything runs.

Each task is given a `Line`, as a spinner's block is. Its detail is drawn after the task's name while it runs, and `line.fail(reason)` marks the task `𝘅 name: reason` and its groups `𝘅`, while the rest of the tree runs on:

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

### Status bar

```ruby
ui.status_bar("deploy", hints: ["^C cancel"]) do
  ui.spinner("Building assets") { build }
  ui.multi_progress("Uploading", concurrent: 2) { |m| ... }
  ui.tasks("Migrate") { |t| ... }
end
```

While the block runs, the bottom of the screen shows how the whole command is doing, under a rule: what started last, how many things are running, done and failed, a bar over every progress bar so far, the elapsed time, and your hints at the right edge. Everything the widgets print scrolls above it, and it disappears when the block ends:

```text
✓ Building assets (0.2s)
[⠙] Uploading    [◼◼◼◼◼◼◼◼◼◼◼◼◼◼                         ]  37%   49/132  ETA 0.3s
├─ [✓] app.js 40/40 (0.2s)
├─ [⠙] app.css   [◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼◼          ]  75%     9/12  ETA 0.1s
└─ [⠙] fonts.zip [                                       ]   0%     0/80  ETA --
──────────────────────────────────────────────────────────────────────────────────────────
 ⠸ deploy · fonts.zip · 2 running · 2 done · [◼◼◼       ] 37% · 0.4s            ^C cancel
```

Nothing reports to it by hand: every `spinner`, `progress`, `multi_spinner`, `multi_progress` and task started inside the block does so on its own. Hints that do not fit are left out, and a status that does not fit is cut short with `…`.

It sets no scroll region, so the scrollback keeps everything, and an interrupted command leaves nothing behind. Piped, or without animation, it just runs the block, and a `status_bar` inside another one does the same. Either way it returns the block's value. Write through `ui` while it runs: a bare `puts` lands where the bar is, until the next `ui` call draws the bar again.

Both arguments are optional, and `hints:` takes one string or several:

```ruby
report = ui.status_bar { build_report }                       # no title, no hints
ui.status_bar("sync", hints: "q quit") { sync }
ui.status_bar("sync", hints: ["^C cancel", "? help"]) { sync }
```

### Putting it together

```ruby
class Deploy < Dry::CLI::Command
  include Dry::CLI::UI

  def call(**)
    ui.status_bar("deploy", hints: ["^C cancel"]) do
      assets = ui.spinner("Building assets") { build_assets }

      ui.multi_progress("Uploading", concurrent: 3) do |m|
        assets.each do |asset|
          m.progress(asset.name, total: asset.bytesize) do |bar|
            upload(asset) { |sent| bar.advance(sent) }
          end
        end
      end

      ui.multi_spinner("Warming caches") do |m|
        regions.each do |region|
          m.spinner(region) do |line|
            warm(region) { |host| line.detail = host }
          end
        end
      end
    end

    ui.success "Deployed #{assets.size} assets"
  rescue => e
    ui.error("Deploy failed", e.message)
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

Tables go to `out` and return `nil`. Cells are converted with `to_s`, the header is bold on a colour terminal, `header:` is optional, and an empty `rows` prints nothing. Tables are never truncated or rotated to fit the screen: a table wider than the terminal wraps like any long line.

```ruby
ui.table(User.limit(10).pluck(:email, :created_at))   # no header
```

### Prompts

```ruby
name = ui.prompt("Name?", default: "Alan Turing")
env  = ui.prompt("Environment?", choices: %w[staging production], default: "staging")
tier = ui.prompt("Tier?", choices: { "Free" => :free, "Pro" => :pro })
ui.confirm("Deploy to #{env}?", default: false)
```

- `prompt` returns the answer as a String, or the default for an empty answer.
- With an Array of `choices:`, it returns the chosen name; with a Hash, the value the chosen name maps to (`:pro` above). `default:` is the name of a choice.
- `confirm` returns `true` or `false`, and `default:` is `false` unless given.

When both standard input and `err` are terminals, these use arrow-key menus and line editing (TTY::Prompt). Otherwise they print the question to `err` and read lines from standard input, so answers can be piped:

```bash
printf 'production\ny\n' | mycli deploy
```

In that mode a list of choices is numbered, and an answer may be the number or the name:

```text
Name? [Alan Turing]
Environment?
  1) staging
  2) production
Choose 1-2 [staging]: 2
Tier?
  1) Free
  2) Pro
Choose 1-2: Pro
Deploy to production? (y/N) maybe
Please answer y or n.
Deploy to production? (y/N) yes
```

An answer that matches no choice asks again, and `confirm` accepts `y`, `yes`, `n` and `no` in any case. When the input runs out, a prompt returns its default, or raises `Dry::CLI::UI::NonInteractiveError` if it has none:

```ruby
token = begin
  ui.prompt("API token?")
rescue Dry::CLI::UI::NonInteractiveError
  ENV.fetch("API_TOKEN")
end
```

## Errors

| Error                               | Raised when                                                                                                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Dry::CLI::UI::NonInteractiveError` | a prompt has no answer left to read and no default                                                                           |
| `Dry::CLI::UI::Error`               | never directly: the base class of the gem's own errors, for `rescue Dry::CLI::UI::Error`                                     |
| `ArgumentError`                     | a widget has no block, `total:` is not a non-negative Integer, `concurrent:` is invalid, a level or configuration is unknown |

Errors raised inside a block are never swallowed: the widget marks itself failed and re-raises them.

## Where output goes

| To `out` (results)                                          | To `err` (everything else)                                                                                                  |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `info`, `success`, `box`, `table`, `status` at those levels | `debug`, `warn`, `error`, `fatal`, `popup`, spinners, progress bars, their multi forms, task trees, the status bar, prompts |

`mycli export > rules.csv` therefore writes only the command's results to the file, while its progress stays on the screen. `ui` writes to the streams dry-cli was called with, so `Dry::CLI.new(registry).call(out: io, err: io)` captures everything.

A stream that is not a terminal, or runs under `TERM=dumb`, gets no animation, no cursor movement and no escape codes. [`NO_COLOR`](https://no-color.org) turns colour off and leaves animation on.

## Configuration

Spinners and bars look the same everywhere, and are set once for the whole process:

```ruby
Dry::CLI::UI.configure do
  spinner_format :dots                                 # any TTY::Spinner format name
  bar_format(complete: "◼", incomplete: " ")           # or any TTY::ProgressBar bar format name, such as :box
  bar_color :green                                     # the finished part: any Pastel style, or nil
  bar_background :on_bright_black                      # the whole bar: any Pastel style, or nil
end
```

Those are the defaults: spinners turn through `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` ten times a second, and bars draw a green `◼` for each finished part on a gray track. Without colour the track is blank, and the brackets still show where the bar ends. Every spinner reads the same format, including `multi_spinner`, task trees and the status bar, and every bar reads the same characters and colours. The formats also take a definition of your own:

```ruby
Dry::CLI::UI.configure do |config|
  config.spinner_format = { interval: 8, frames: %w[◐ ◓ ◑ ◒] }   # frames per second, and the frames
  config.bar_format = { complete: "#", incomplete: "." }
end
```

An unknown name or a malformed definition raises `ArgumentError` when it is set, as does a colour Pastel does not know:

```ruby
Dry::CLI::UI.configure { bar_color :nope }
# => ArgumentError: bar_color must be a Pastel style or nil, got :nope
```

Called without a value, each setting reads it back, and `Dry::CLI::UI.config` returns the configuration itself. `Dry::CLI::UI.reset!` restores every default, which is useful between specs:

```ruby
Dry::CLI::UI.config.bar_color        # => :green
Dry::CLI::UI.config.spinner_frames   # => ["⠋", "⠙", "⠹", ...]

RSpec.configure { |c| c.after { Dry::CLI::UI.reset! } }
```

Some more looks, all from names the TTY gems already know:

```ruby
Dry::CLI::UI.configure do
  spinner_format :classic          # | / - \
  bar_format :block                # █ and ░
  bar_color :cyan
  bar_background nil               # no track colour
end
```

### Console options

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

Every option `Console.new` takes:

| Option       | Default               | What it does                                                         |
| ------------ | --------------------- | -------------------------------------------------------------------- |
| `out:`       | `$stdout`             | where results go                                                     |
| `err:`       | `$stderr`             | where diagnostics, progress and prompts go                           |
| `input:`     | `$stdin`              | where prompt answers are read from                                   |
| `env:`       | `ENV`                 | read for `NO_COLOR` and `TERM`                                       |
| `color:`     | `nil`                 | `true` or `false` forces colour on both streams; `nil` detects it    |
| `animate:`   | `nil`                 | `true` or `false` forces animation on both streams; `nil` detects it |
| `width:`     | `nil`                 | forces the terminal width in columns; `nil` asks the terminal, or 80 |
| `box_width:` | `nil`                 | the width of every box; `nil` fills the terminal less two columns    |
| `clock:`     | monotonic clock       | any object whose `call` returns seconds, for elapsed times           |
| `config:`    | `Dry::CLI::UI.config` | a `Dry::CLI::UI::Configuration` for this console alone               |

`config:` gives one console a look of its own without changing the process-wide one:

```ruby
classic = Dry::CLI::UI::Configuration.new.tap { |c| c.spinner_format = :classic }
ui = Dry::CLI::UI::Console.new(config: classic)
```

### Testing a command

Pass `StringIO`s and assert on what was written. A `StringIO` is not a terminal, so the output is the plain form shown throughout this README, with no escape codes:

```ruby
out = StringIO.new
err = StringIO.new
ui  = Dry::CLI::UI::Console.new(out: out, err: err, input: StringIO.new("y\n"))

ui.spinner("Loading") { :ok }
ui.success "Imported"
ui.confirm("Continue?")        # => true

err.string   # => "Loading...\n✓ Loading (0.0s)\nContinue? (y/N) "
out.string   # => the Success box
```

Through dry-cli, `Dry::CLI.new(registry).call(arguments: %w[import], out: out, err: err)` gives every command's `ui` those streams.

## Relationship to dry-cli-help

`dry-cli-help` is static presentation: what does this command do? `dry-cli-ui` is runtime presentation: what is this command doing? Use either, or both.

```ruby
gem "dry-cli"
gem "dry-cli-help"
gem "dry-cli-ui"
```

## Examples

[`examples/`](examples/README.md) holds a small dry-cli application that uses the gem:

```bash
cd examples
bundle install
bundle exec bin/mycli primes --max 200000
bundle exec bin/mycli urls_spinner https://www.ruby-lang.org https://dry-rb.org
bundle exec bin/mycli urls_progress https://www.ruby-lang.org https://dry-rb.org
bundle exec bin/mycli urls_progress https://www.ruby-lang.org | cat   # the plain form
```

## Development

```bash
bin/setup               # bundle install
just test               # the suite, with 100% line and branch coverage enforced
just lint               # rubocop
just ci                 # both
just format             # rubocop -a, then mdformat
just doc                # YARD documentation
bin/console             # IRB with the gem loaded
```

Specs render into a `StringIO`. The animated code paths run against `FakeTTY`, a `StringIO` that answers `tty?` with true, and elapsed times come from a fake clock. RBS signatures for the public API are in [`sig/dry/cli/ui.rbs`](sig/dry/cli/ui.rbs).

## Contributing

Bug reports and pull requests are welcome at <https://github.com/kigster/dry-cli-ui>.

> [!WARNING]
> The `dry-` prefix and the `Dry::CLI::UI` namespace do not imply endorsement by `dry-rb`. This is an independent gem that extends theirs.

## Note to Dry-Rb Maintainers

First — hats off to all of you who tirelessly built out one of the most valuable collections of libraries in the Ruby ecosystem.

While I admire and would be willing to contribute any or all of the extension gem's code to the original gem, I feel that creating plugins and extensions allows the author to fully express their needs and wants, and then, if the authors of `dry-cli` become interested in any of them, I would be honored to submit a PR to `dry-cli` itself.

This method offered a very open road to extensibility and experimentation. If the code quality or design is not up to the level required for direct contributions to `dry-rb`, then let it be known that:

1. We would be very happy to receive any feedback and improve, refactor, and update the gem assuming it improves it
1. Roll any part of the codebase as a PR to the `dry-cli` core.
1. We hold the authors of `dry-rb` in high regard, and generally would love to collaborate, as long as the feedback loop/cycle is not so long that the context of the changes gets lost in time, as with so many contributions made to other gems in the past.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
