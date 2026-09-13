# frozen_string_literal: true

require_relative "lib/dry/cli/ui/version"

Gem::Specification.new do |spec|
  spec.name = "dry-cli-ui"
  spec.version = Dry::CLI::UI::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "Runtime terminal UI for dry-cli commands: spinners, progress, boxes, task trees, tables, prompts"
  spec.description = <<~DESC.tr("\n", " ").strip
    Include one module in a Dry::CLI command and call ui.info, ui.error, ui.spinner, ui.progress,
    ui.tasks, ui.table or ui.prompt. Falls back to plain text when the output is not a terminal.
    Built on the TTY toolkit. Not affiliated with dry-rb.
  DESC
  spec.homepage = "https://github.com/kigster/dry-cli-ui"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[. bin/ docs/ spec/ Gemfile Rakefile justfile lefthook.yml CLAUDE.md])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "dry-cli", ">= 1.0"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "strings", "~> 0.2"
  spec.add_dependency "tty-box", "~> 0.7"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-progressbar", "~> 0.18"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-screen", "~> 0.8"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "tty-table", "~> 0.12"
end
