# frozen_string_literal: true

# simplecov first, so loading the app is measured.
require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__), File.expand_path('../dev', __dir__)
require 'puri'
require 'puri/dummy'

# GTK stays unloaded here: Core and Protocol specs run without it, and a spec that needs it
# requires gtk_helper.
RSpec.configure do |config|
  config.expect_with :minitest
  config.disable_monkey_patching!
end
