# frozen_string_literal: true

module Dry
  class CLI
    module UI
      # The renderers behind {Console}. Each one takes a {Terminal} and owns
      # both its rich form and its plain fallback. Nothing outside this
      # namespace touches a TTY toolkit class.
      module Widgets
        autoload :Box, File.expand_path("widgets/box", __dir__)
        autoload :Multi, File.expand_path("widgets/multi", __dir__)
        autoload :MultiProgress, File.expand_path("widgets/multi_progress", __dir__)
        autoload :MultiSpinner, File.expand_path("widgets/multi_spinner", __dir__)
        autoload :Pool, File.expand_path("widgets/pool", __dir__)
        autoload :Outcome, File.expand_path("widgets/outcome", __dir__)
        autoload :Progress, File.expand_path("widgets/progress", __dir__)
        autoload :Prompt, File.expand_path("widgets/prompt", __dir__)
        autoload :Spinner, File.expand_path("widgets/spinner", __dir__)
        autoload :Status, File.expand_path("widgets/status", __dir__)
        autoload :Table, File.expand_path("widgets/table", __dir__)
        autoload :Tasks, File.expand_path("widgets/tasks", __dir__)
      end
    end
  end
end
