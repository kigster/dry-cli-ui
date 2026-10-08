# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dry-cli-ui.gemspec

gemspec

# dry-cli with public stream and plugin hooks (kigster/dry-cli#1 to #4), until they are released.
# DRY_CLI_PATH points at a local checkout instead; DRY_CLI_SOURCE=rubygems takes the latest
# release, as the gemspec allows.
if ENV["DRY_CLI_PATH"]
  gem "dry-cli", path: ENV["DRY_CLI_PATH"]
elsif ENV["DRY_CLI_SOURCE"] != "rubygems"
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
