# Examples

A small `dry-cli` app, `bin/mycli`, with two commands that show off the UI widgets.

First:

```bash
bundle install
```

## Help

```bash
$ bundle exec bin/mycli -h
USAGE
  mycli COMMAND [OPTIONS]

COMMANDS
  version, v     Print version
  download-urls   Download URLs, each to its own file
  find-hosts     Find hosts on the local network that answer on TCP ports

OPTIONS
  -h, --help     Show help
  -v, --version  Print version
```

## Commands to Try

- `download-urls URL1 URL2 ...` downloads each URL to its own file in the current folder, under a spinner per URL.
- `download-urls -u urls.txt` reads the URLs from `urls.txt`, one per line, skipping blank lines and `#` comments. URLs given as arguments are downloaded too. Invalid URLs, from either place, are skipped and listed in a warning at the end.
- `download-urls --progress --save-to=downloads URL1 URL2 ...` shows a progress bar per URL instead, and saves the files in `downloads/`, creating it when missing.
- `find-hosts` probes every address on the local /24 subnet on the common TCP ports (22, 53, 80, 123, 139, 443, 445, 631, 3389, 5000, 7000), 10 addresses at a time, with a spinner per address. It ends with a box listing each host that answered and its open ports.
- `find-hosts --progress --output=hosts.txt` shows two bars instead, one counting the addresses that answered and one those that did not, and also writes the result to `hosts.txt`.
- `find-hosts --port=22` probes only port 22, with the two bars.

`download-urls` downloads at most 10 URLs at a time. `--progress` and `--spinner` are mutually exclusive. `download-urls` defaults to a spinner. `find-hosts` defaults to spinners, or to progress bars with `--port`.

## File names

`download-urls` names each file after the URL's host, path and query, with anything unsafe replaced by `_`:

| URL                                                     | File                                            |
| ------------------------------------------------------- | ----------------------------------------------- |
| `https://www.ruby-lang.org/images/header-ruby-logo.png` | `www.ruby-lang.org_images_header-ruby-logo.png` |
| `https://example.com`                                   | `example.com.html`                              |
| `https://httpbin.org/json`                              | `httpbin.org_json.json`                         |

A file keeps the extension its URL path has. Without one, the extension comes from the response's `Content-Type`, and is `.txt` for a type the command does not know.
