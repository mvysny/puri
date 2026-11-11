# frozen_string_literal: true

require 'gtk_helper'

# The whole UI against the dummy Core, wired as exe/puri wires it.
RSpec.describe 'Puri::Desktop::PopupWindow' do
  p = Puri::Protocol

  let(:pace) { 0 }
  let(:core) { Puri::Core::DummyCore.new(think: 0, pace:, title_delay: 0) { |event| client.deliver(event) } }
  let(:client) { Puri::Desktop::BackendClient.new(core) }
  let(:window) { Puri::Desktop::PopupWindow.new(GTK_APP, client) }
  let(:view) { window.conversation_view }

  after do
    window.destroy
    core.close
  end

  # @param text [String]
  # @return [void]
  def ask(text)
    view.entry.text = text
    view.entry.signal_emit('activate')
  end

  # @return [void]
  def wait_for_idle
    wait_until('the turn ends') { view.conversation && !view.activity.running? && !core_running? }
  end

  # @return [Boolean]
  def core_running? = core.load_conversation(view.conversation).activity.running?

  it 'opens as the pill: the entry alone' do
    window.present
    refute window.expanded?
    refute view.transcript.visible?
    assert window.has_css_class?('pill')
  end

  it 'expands on the first question, streams the answer, and takes the title' do
    window.present
    ask('  how do I keep an avocado?  ')
    assert window.expanded?
    assert view.transcript.visible?
    assert_equal '', view.entry.text
    wait_until('the answer is shown') { view.transcript.blocks.last.is_a?(p::Reply) && !view.activity.running? }
    assert_equal 'how do I keep an avocado?', view.transcript.blocks.first.text
    wait_until('the title lands') { window.header_title == 'How do I keep an avocado' }
  end

  it 'ignores Enter on an empty entry' do
    ask('   ')
    refute window.expanded?
    assert_empty core.list_conversations
  end

  context 'with a confirmation pending' do
    before do
      ask('reschedule the dentist in my calendar')
      wait_until('it asks') { view.activity.state == 'confirming' }
    end

    let(:confirmation) { view.transcript.blocks.grep(p::Confirmation).last }

    it 'approves through the button' do
      view.transcript.row(confirmation.id).approve_button.signal_emit('clicked')
      wait_for_idle
      assert_equal 'approved', view.transcript.blocks.find { _1.id == confirmation.id }.state
    end

    it 'redirects with typed words, which never press a button' do
      ask('make it Friday')
      wait_until('it asks again') { view.transcript.blocks.grep(p::Confirmation).last.id != confirmation.id }
      assert_equal 'redirected', view.transcript.blocks.find { _1.id == confirmation.id }.state
    end

    it 'cancels and hides on Escape' do
      window.present
      window.activate_action('escape', nil)
      refute window.visible?
      wait_until('Core cancelled it') { !core.list_conversations.first.running }
      assert_equal 'cancelled', core.load_conversation(confirmation_conversation).blocks
                                    .grep(p::Confirmation).last.state
    end

    # @return [String] the conversation, read from Core: hiding forgot it
    def confirmation_conversation = core.list_conversations.first.id
  end

  context 'while a reply streams' do
    let(:pace) { 0.01 }

    it 'stops it on the first Escape and stays open; the second Escape hides' do
      window.present
      ask('something long')
      wait_until('words arrive') { view.activity.state == 'streaming' }
      window.activate_action('escape', nil)
      assert window.visible?
      wait_until('the cancel lands') { view.transcript.blocks.last.is_a?(p::Notice) }
      assert_equal 'Cancelled', view.transcript.blocks.last.text
      window.activate_action('escape', nil)
      refute window.visible?
    end
  end

  it 'comes back as an empty pill after hiding, and Up recalls the last question' do
    window.present
    ask('hi there')
    wait_for_idle
    window.activate_action('hide', nil)
    window.present
    refute window.expanded?
    assert_nil view.conversation
    assert view.entry.recall_question
    assert_equal 'hi there', view.entry.text
  end

  it 'leaves a running turn alone on ×' do
    window.present
    ask('reschedule the dentist in my calendar')
    wait_until('it asks') { view.activity.state == 'confirming' }
    window.activate_action('hide', nil)
    sleep 0.05
    assert core.list_conversations.first.running
  end

  it 'starts a new conversation on Ctrl+N, in the expanded window' do
    ask('hi')
    wait_for_idle
    window.activate_action('new-conversation', nil)
    assert window.expanded?
    assert_nil view.conversation
    assert view.transcript.empty?
    ask('again')
    wait_until('a second conversation') { core.list_conversations.size == 2 }
  end

  it 'opens the history, wider, and loads a conversation picked there' do
    window.present
    ask('first question')
    wait_for_idle
    first = view.conversation
    window.activate_action('new-conversation', nil)
    ask('second question')
    wait_for_idle

    width = window.default_width
    window.activate_action('toggle-history', nil)
    assert window.history_visible?
    assert_equal width + Puri::Desktop::PopupWindow::SIDEBAR_WIDTH, window.default_width
    wait_until('both are listed') { window.sidebar.rows.size == 2 }

    row = window.sidebar.rows.find { _1.summary.id == first }
    window.sidebar.list.signal_emit('row-activated', row)
    assert_equal first, view.conversation
    assert_equal 'first question', view.transcript.last_question

    window.activate_action('toggle-history', nil)
    assert_equal width, window.default_width
  end

  it 'opens the history on Ctrl+F, even from the pill' do
    window.present
    window.activate_action('search', nil)
    assert window.expanded?
    assert window.history_visible?
  end
end
