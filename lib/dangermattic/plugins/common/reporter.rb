# frozen_string_literal: true

module Danger
  # Handles reporting messages in the context of Danger, allowing the generation of
  # warnings, errors, and simple messages in a Danger run.
  #
  # @example Reporting a Warning
  #   reporter.report(message: "This is a warning message", type: :warning)
  #
  # @example Reporting an Error
  #   reporter.report(message: "This is an error message", type: :error)
  #
  # @see Automattic/dangermattic
  # @tags tool, util, danger
  #
  class Reporter < Plugin
    # Report a message to be posted by Danger as an error (failing the build), a warning or a simple message.
    #
    # @param message [String] The message to be reported to Danger.
    # @param type [Symbol] The type of report. Possible values:
    #                        - :warning (default): Reports a warning.
    #                        - :error: Reports an error.
    #                        - :message: Reports a simple message.
    #                        - :none or nil: Takes no action.
    #
    # @return [void]
    def report(message:, type: :warning)
      return if message.nil? || message.empty? || type.nil?

      case type
      when :error
        failure(message)
      when :warning
        warn(message)
      when :message
        danger.message(message)
      end
    end
  end
end
