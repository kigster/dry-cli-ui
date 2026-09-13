# frozen_string_literal: true

require "tty-prompt"

module Dry
  class CLI
    module UI
      module Widgets
        # Questions, choices and yes/no confirmations.
        #
        # When both the input and the output are interactive terminals, this
        # uses arrow-key menus and line editing. Otherwise it prints the
        # question and reads a line, so answers can be piped in:
        #
        #   printf 'production\ny\n' | mycli deploy
        #
        # An exhausted input returns the default. A question without a
        # default raises {NonInteractiveError} rather than inventing an answer.
        class Prompt
          # @param input [IO] where answers come from
          # @param terminal [Terminal] where questions go
          # @param backend [TTY::Prompt, nil] the interactive implementation; built on first use when nil
          def initialize(input:, terminal:, backend: nil)
            @input = input
            @terminal = terminal
            @backend = backend
          end

          # Asks for a free-form answer, or for one of a list of choices.
          #
          # @param question [String]
          # @param default [Object, nil] returned for an empty answer; for choices, the name of one
          # @param choices [Array<String>, Hash{String => Object}, nil]
          #   names to pick from, or names mapped to the values to return
          # @return [Object, nil] the answer, or the chosen value
          # @raise [NonInteractiveError] when the input is exhausted and there is no default
          def ask(question, default: nil, choices: nil)
            if interactive?
              options = default.nil? ? {} : { default: default }
              choices ? backend.select(question, choices, **options) : backend.ask(question, **options)
            else
              choices ? plain_select(question, pairs(choices), default) : plain_ask(question, default)
            end
          end

          # Asks a yes/no question.
          #
          # @param question [String]
          # @param default [Boolean] returned for an empty answer or an exhausted input
          # @return [Boolean]
          def confirm(question, default: false)
            return backend.yes?(question, default: default) if interactive?

            loop do
              terminal.print("#{question} #{default ? '(Y/n)' : '(y/N)'} ")
              case read&.downcase
              in nil | "" then return default
              in "y" | "yes" then return true
              in "n" | "no" then return false
              else terminal.puts("Please answer y or n.")
              end
            end
          end

          private

          # @return [IO]
          attr_reader :input

          # @return [Terminal]
          attr_reader :terminal

          # @return [TTY::Prompt]
          def backend
            @backend ||= TTY::Prompt.new(
              input: input,
              output: terminal.io,
              enable_color: terminal.color?,
              interrupt: :signal
            )
          end

          # @return [Boolean]
          def interactive?
            input.respond_to?(:tty?) && input.tty? && terminal.animated?
          end

          # @return [String, nil] the next line without surrounding whitespace, or nil at the end of input
          def read
            input.gets&.strip
          end

          # @param question [String]
          # @param default [Object, nil]
          # @return [Object, nil]
          def plain_ask(question, default)
            terminal.print("#{question}#{" [#{default}]" unless default.nil?} ")
            answer = read
            raise NonInteractiveError, "no answer for #{question.inspect} and no default" if answer.nil? && default.nil?

            answer.nil? || answer.empty? ? default : answer
          end

          # @param question [String]
          # @param options [Array<Array(String, Object)>]
          # @param default [Object, nil] the name of the default choice
          # @return [Object]
          def plain_select(question, options, default)
            terminal.puts(question)
            options.each_with_index { |(name, _), index| terminal.puts("  #{index + 1}) #{name}") }
            loop do
              terminal.print("Choose 1-#{options.size}#{" [#{default}]" unless default.nil?}: ")
              line = read
              answer = line.nil? || line.empty? ? default&.to_s : line
              found = choice(options, answer) if answer
              return found.last if found
              raise NonInteractiveError, "no valid choice for #{question.inspect}" if line.nil?

              terminal.puts("Choose a number from 1 to #{options.size}, or type a choice.")
            end
          end

          # @param options [Array<Array(String, Object)>]
          # @param answer [String] a 1-based position or a name
          # @return [Array(String, Object), nil]
          def choice(options, answer)
            return options[answer.to_i - 1] if answer.match?(/\A\d+\z/) && answer.to_i.between?(1, options.size)

            options.find { |name, _| name.to_s == answer }
          end

          # @param choices [Array<String>, Hash{String => Object}]
          # @return [Array<Array(String, Object)>]
          def pairs(choices)
            choices.is_a?(Hash) ? choices.to_a : choices.map { |name| [name, name] }
          end
        end
      end
    end
  end
end
