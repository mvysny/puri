# frozen_string_literal: true

require 'gtk_helper'

RSpec.describe 'Puri::Desktop::HistorySidebar' do
  let(:core) { Puri::Dummy::Backend.new(seed: true, title_delay: 0) { |event| client.deliver(event) } }
  let(:client) { Puri::Desktop::BackendClient.new(core) }
  let(:sidebar) { Puri::Desktop::HistorySidebar.new(client) }

  after { core.close }

  it 'lists every conversation, newest first' do
    assert_equal(['When is the dentist', 'What is on my shopping note', 'How do I keep an avocado'],
                 sidebar.rows.map { _1.summary.title })
  end

  it 'filters on the titles' do
    shopping = sidebar.rows[1]
    sidebar.search.text = 'SHOPPING'
    wait_until('the filter applies') { !sidebar.rows.first.child_visible? }
    assert shopping.child_visible?
    refute sidebar.rows[2].child_visible?
  end

  it "follows Core's changes" do
    sidebar
    id = client.ask(nil, 'a new one')
    wait_until('it is listed') { sidebar.rows.first.summary.id == id }
  end

  it 'reports a picked conversation, but not one marked from outside' do
    picked = []
    sidebar.on_selected { picked << _1 }
    sidebar.selected = sidebar.rows[2].summary.id
    assert_empty picked
    sidebar.list.select_row(sidebar.rows[0])
    assert_equal [sidebar.rows[0].summary.id], picked
  end

  it 'words the time the way a list of chats does' do
    now = Time.new(2026, 11, 11, 15, 0, 0)
    assert_equal '14:05', Puri::Desktop::HistoryRow.timestamp(Time.new(2026, 11, 11, 14, 5), now)
    assert_equal 'Yesterday', Puri::Desktop::HistoryRow.timestamp(Time.new(2026, 11, 10, 23, 0), now)
    assert_equal 'Sunday', Puri::Desktop::HistoryRow.timestamp(Time.new(2026, 11, 8, 9, 0), now)
    assert_equal 'Oct 2', Puri::Desktop::HistoryRow.timestamp(Time.new(2026, 10, 2, 9, 0), now)
    assert_equal 'Oct 2, 2025', Puri::Desktop::HistoryRow.timestamp(Time.new(2025, 10, 2, 9, 0), now)
  end
end
