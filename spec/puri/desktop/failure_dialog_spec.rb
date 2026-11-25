# frozen_string_literal: true

require 'gtk_helper'

# "Open config.toml" isn't clicked here: it would open the file in this machine's editor.
RSpec.describe Puri::Desktop::FailureDialog do
  message = 'no [titler] names the connection that writes titles'

  it 'shows the message, and offers the config to open' do
    dialog = described_class.new(GTK_APP, message, config: '/home/me/.config/puri/config.toml')
    assert_equal "Puri can't start", dialog.heading
    assert_equal message, dialog.extra_child.label
    assert dialog.has_response?('open')
    assert_equal 'open', dialog.default_response
  end

  it 'offers no file without one' do
    dialog = described_class.new(GTK_APP, message)
    refute dialog.has_response?('open')
    assert_equal 'quit', dialog.default_response
  end

  it "is the app's window until it closes" do
    dialog = described_class.new(GTK_APP, message)
    before = GTK_APP.windows.size
    dialog.present
    assert_equal before + 1, GTK_APP.windows.size
    dialog.close
    wait_until('its window is gone') { GTK_APP.windows.size == before }
  end
end
