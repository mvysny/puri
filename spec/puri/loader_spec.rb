# frozen_string_literal: true

require 'gtk_helper'

RSpec.describe Puri::LOADER do
  # Zeitwerk's own check that every file under lib/ defines the constant its path names.
  it 'eager-loads the whole app' do
    Puri::LOADER.eager_load(force: true)
    assert defined?(Puri::Desktop::PopupWindow)
  end
end
