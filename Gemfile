# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dry-cli-ui.gemspec

# dry-cli with public stream and plugin hooks (kigster/dry-cli#1 to #4), until they are released.
# DRY_CLI_PATH points at a local checkout instead.
if ENV["DRY_CLI_PATH"]
  gem "dry-cli", path: ENV["DRY_CLI_PATH"]
else
  gem "dry-cli", github: "kigster/dry-cli", branch: "kig/auto-inject-compatibility"
end
gemspec

# dry-cli with public stream and plugin hooks (kigster/dry-cli#1 to #4), until they are released.
# DRY_CLI_PATH points at a local checkout instead.
if ENV["DRY_CLI_PATH"]
  gem "dry-cli", path: ENV["DRY_CLI_PATH"]
else
  gem "dry-cli", github: "kigster/dry-cli", branch: "kig/auto-inject-compatibility"
end

group :development, :test do
  gem "coverage-badge"
  gem "irb"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "rspec-its"
  gem "rubocop"
  gem "simplecov"
  gem "yard"
end
