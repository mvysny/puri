# frozen_string_literal: true

require 'monitor'
require 'puri'

module Puri
  # The dummy backend: {Backend} answers from canned {Script}s, for the GTK specs and for walking
  # the UI with no model. Development only: it lives in `dev/`, outside Zeitwerk's `lib/`, and
  # loads only when `dev/` is on the load path, as `exe/puri --dummy` and the specs put it:
  #
  #   $LOAD_PATH.unshift File.expand_path('dev', root)
  #   require 'puri/dummy'
  #   Puri::Dummy::Backend.new(seed: true) { |event| client.deliver(event) }
  module Dummy
  end
end

require_relative 'dummy/script'
require_relative 'dummy/turn'
require_relative 'dummy/backend'
