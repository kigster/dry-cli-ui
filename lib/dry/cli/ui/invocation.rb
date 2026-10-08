# frozen_string_literal: true

require "fileutils"

module Dry
  class CLI
    module UI
      # How a command was run, as far as naming its report and log files goes: the program, the
      # command's names, when the process started, and where.
      #
      # @!attribute [r] executable
      #   @return [String] the program's basename, e.g. `law-cli`
      # @!attribute [r] action
      #   @return [String, nil] the command's names joined with `-`, e.g. `generate-text`; nil for a
      #     CLI that is a single command
      # @!attribute [r] name
      #   @return [String] what the command's logger is called, usually its class name
      # @!attribute [r] started_at
      #   @return [Time] when the process started; stamps the report's file name
      # @!attribute [r] directory
      #   @return [String] the directory the command runs in
      Invocation = ::Data.define(:executable, :action, :name, :started_at, :directory) do
        # Describes a command: by the names dry-cli resolved it by, when {Flags::Hook} recorded
        # them, and otherwise by its class name.
        #
        # @param command [Object, nil] the command, or nil for none
        # @param program [String] the program's path
        # @param started_at [Time]
        # @param directory [String]
        # @return [Invocation]
        def self.for(command = nil, program: $PROGRAM_NAME, started_at: UI.started_at, directory: Dir.pwd)
          executable = File.basename(program)
          class_name = command.class.name unless command.nil?
          new(executable: executable, action: action(command, class_name), name: class_name || executable,
              started_at: started_at, directory: directory)
        end

        # The names the command was called by, else the last part of its class name, dasherized.
        #
        # @param command [Object, nil]
        # @param class_name [String, nil]
        # @return [String, nil]
        def self.action(command, class_name)
          names = command.instance_variable_get(:@ui_command_names)
          return names.join("-") if names
          return if class_name.nil?

          class_name.split("::").last.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase
        end
        private_class_method :action

        # The nearest directory up from `directory` that holds `.git`, else `directory` itself.
        #
        # @param directory [String]
        # @return [String]
        def self.root(directory)
          start = Pathname(directory).expand_path
          (start.ascend.find { it.join(".git").exist? } || start).to_s
        end

        # The program and the action, joined with `-`: `law-cli-generate-text`.
        #
        # @return [String]
        def basename
          [executable, action].reject { it.nil? || it.empty? }.join("-")
        end

        # Where `-o` writes. Creates the file's directory when it is missing.
        #
        # @param value [String, nil] what `-o` was given: nil without `-o`, `-` for STDOUT, an
        #   empty string for the default name, or a path
        # @return [String, nil] the path, or nil for the command's own output
        def report_path(value)
          stamp = started_at.strftime("%Y-%m-%d.%H%M%S")
          file(value, "#{basename}.#{stamp}.log") unless value.nil? || value == "-"
        end

        # Where `-l` logs. Creates the file's directory when it is missing.
        #
        # @param value [String, nil] what `-l` was given: nil without `-l`, `-` for STDOUT, an
        #   empty string for the default name, or a path
        # @return [String, nil] the path, `-` for STDOUT, or nil for no log
        def log_path(value)
          value.nil? || value == "-" ? value : file(value, "#{basename}.log")
        end

        private

        # @param value [String] a path, or empty for the default
        # @param default [String] the default file name, under `log/` at the repository root
        # @return [String]
        def file(value, default)
          path = value.empty? ? File.join(Invocation.root(directory), "log", default) : File.expand_path(value, directory)
          FileUtils.mkdir_p(File.dirname(path))
          path
        end
      end
    end
  end
end
