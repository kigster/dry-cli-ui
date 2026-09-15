# Examples

These examples offers two commands that are are indicative of the added behavior.

But first,

```bash
bundle install
```

Then:

## Help

```bash
$ bundle exec bin/mycli -h
USAGE
  mycli COMMAND [OPTIONS]

COMMANDS
  version, v     Print version
  urls_progress  Fetch URLs with a progress bar each, and write them all to urls.txt
  urls_spinner   Fetch URLs with a spinner each, and write each to its own file
  primes         Compute closest prime to a given number in the array

OPTIONS
  -h, --help     Show help
  -v, --version  Print version
```

## Commands to Try

- primes
- urls_progress url1 url2 ...
- urls_spinner url1 url2 ...
