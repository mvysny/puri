# frozen_string_literal: true

require 'gtk_helper'

RSpec.describe 'Puri::Desktop::TranscriptView' do
  p = Puri::Protocol

  let(:answers) { [] }
  let(:view) { Puri::Desktop::TranscriptView.new { |id, approved| answers << [id, approved] } }

  # @return [Array<Gtk::Widget>] the column's rows, the progress row and the queued messages last
  def rows
    column = view.child.child.child # the viewport ScrolledWindow adds, the clamp, the column
    child = column.first_child
    [].tap do |all|
      while child
        all << child
        child = child.next_sibling
      end
    end
  end

  it 'shows a transcript, one row per block, in order' do
    view.transcript = p::Transcript.new(
      conversation: 'c1', title: 'Avocados', activity: p::Activity::IDLE,
      status: p::Status.new(model: 'Ornith 1.5'),
      blocks: [p::UserMessage.new(id: 'b1', text: 'avocado?'),
               p::ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado"', error: false),
               p::Reply.new(id: 'b3', parts: [p::Prose.new(markup: '<b>cold</b>')]),
               p::Notice.new(id: 'b4', text: 'Cancelled', error: false)]
    )
    assert_equal(%w[UserMessageRow ToolLineRow ReplyView NoticeRow ProgressRow QueuedMessages],
                 rows.map { _1.class.name.split('::').last })
    assert_equal 'avocado?', view.last_question
  end

  it 'replaces a block in place, appends a new one before the progress row' do
    view.upsert(p::Reply.new(id: 'b1', parts: [p::Prose.new(markup: 'Keep')]))
    prose = view.row('b1').first_child
    view.upsert(p::Reply.new(id: 'b1', parts: [p::Prose.new(markup: 'Keep it <b>cold</b>')]))
    assert_same prose, view.row('b1').first_child, 'a streamed delta updates the same label'
    assert_equal 'Keep it cold', prose.text

    view.upsert(p::Notice.new(id: 'b2', text: 'Cancelled', error: false))
    assert_equal [view.row('b1'), view.row('b2')], rows.first(2)
    assert_kind_of Puri::Desktop::ProgressRow, rows[-2]
  end

  it 'draws code and tables as widgets of their own' do
    view.upsert(p::Reply.new(id: 'b1', parts: [p::Code.new(text: 'x < y'),
                                               p::Table.new(header: %w[A B], rows: [%w[1 2]])]))
    code = view.row('b1').first_child
    table = view.row('b1').last_child
    assert_kind_of Puri::Desktop::CodeBlock, code
    assert_equal 'x < y', code.child.child.text
    assert_equal '2', table.grid.get_child_at(1, 1).text
  end

  it 'drops a removed block, and ignores one it never showed' do
    view.upsert(p::UserMessage.new(id: 'b1', text: 'hi'))
    view.remove('b1')
    view.remove('nope')
    assert view.empty?
  end

  it 'shows the progress and its status only while the turn works' do
    progress = rows[-2]
    view.activity = p::Activity.new(state: 'working', status: 'Searching the web…')
    assert progress.visible?
    assert_equal 'Searching the web…', progress.status
    view.activity = p::Activity.new(state: 'streaming')
    refute progress.visible?
  end

  it 'shows the messages the agent has not read yet at the bottom, dimmed, until it reads them' do
    queued = rows.last
    refute queued.visible?
    view.pending = ['and bananas?', 'and limes?']
    assert queued.visible?
    bubbles = queued.first_child
    texts = [bubbles.first_child, bubbles.last_child].map { _1.first_child.text }
    assert_equal ['and bananas?', 'and limes?'], texts
    assert queued.has_css_class?('puri-queued')

    view.upsert(p::UserMessage.new(id: 'b1', text: 'and bananas?'))
    view.pending = ['and limes?']
    assert_equal [view.row('b1'), queued], [rows.first, rows.last]
    view.pending = []
    refute queued.visible?
  end

  it 'takes the queued messages from a transcript loaded' do
    view.transcript = p::Transcript.new(conversation: 'c1', title: 'Avocados', activity: p::Activity::IDLE,
                                        status: p::Status.new(model: 'Ornith 1.5'), blocks: [],
                                        pending: ['and bananas?'])
    assert_equal ['and bananas?'], view.pending
    view.transcript = nil
    assert_empty view.pending
  end

  it 'answers a confirmation through its buttons, then shows the outcome' do
    pending = p::Confirmation.new(id: 'b1', question: 'Move “Dentist”?', approve_label: 'Update',
                                  destructive: true, state: 'pending')
    view.upsert(pending)
    row = view.row('b1')
    assert row.approve_button.has_css_class?('destructive-action')
    row.approve_button.signal_emit('clicked')
    assert_equal [%w[b1] + [true]], answers

    view.upsert(pending.with(state: 'approved'))
    refute row.approve_button.parent.visible?
  end
end
