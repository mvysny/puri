# frozen_string_literal: true

require 'gtk_helper'

RSpec.describe 'Puri::Desktop::PopupWindow' do
  let(:commands) { [] }
  let(:client) { Puri::Desktop::BackendClient.new { |command| commands << command } }
  let(:window) { Puri::Desktop::PopupWindow.new(GTK_APP, client) }

  after { window.destroy }

  it 'asks on Enter, and clears the entry' do
    window.entry.text = '  avocado?  '
    window.entry.signal_emit('activate')
    assert_equal [Puri::Protocol::Ask.new(conversation: nil, text: 'avocado?')], commands
    assert_equal '', window.entry.text
  end

  it 'ignores Enter on an empty entry' do
    window.entry.text = '   '
    window.entry.signal_emit('activate')
    assert_empty commands
  end

  it "streams its conversation's reply, delivered from another thread" do
    window
    Thread.new do
      client.deliver(Puri::Protocol::TurnStarted.new(conversation: 'c1'))
      client.deliver(Puri::Protocol::TextDelta.new(conversation: 'c1', text: 'Lorem'))
      client.deliver(Puri::Protocol::TextDelta.new(conversation: 'other', text: ' nope'))
      client.deliver(Puri::Protocol::TextDelta.new(conversation: 'c1', text: ' ipsum'))
      client.deliver(Puri::Protocol::TurnFinished.new(conversation: 'c1'))
    end.join
    wait_until('the reply arrives') { window.reply_text == 'Lorem ipsum' }

    window.entry.text = 'more'
    window.entry.signal_emit('activate')
    assert_equal Puri::Protocol::Ask.new(conversation: 'c1', text: 'more'), commands.last
  end
end
