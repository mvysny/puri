# frozen_string_literal: true

RSpec.describe Puri::Core::ReplyStream do
  p = Puri::Protocol

  reply = <<~MD
    Ripe ones go to the **fridge**.

    - loose list, first item

    - second item

    ```sh
    ripen --paper-bag

    done
    ```

    | Where | Days |
    |—-|—-|
    | fridge | 3 |

    Enjoy.
  MD

  it 'ends, word by word, in the parts of the whole reply' do
    stream = described_class.new
    reply.scan(/\s*\S+/).each { stream.append(_1) }
    assert_equal Puri::Core::ReplyRenderer.render(reply), stream.finish
  end

  it 'merges, after every delta, into the whole text so far' do
    stream = described_class.new
    source = +''
    reply.scan(/\s*\S+/).each do |word|
      source << word
      assert_equal Puri::Core::ReplyRenderer.render(source), Puri::Core::ReplyRenderer.merge(stream.append(word)),
                   "after #{source.inspect}"
    end
  end

  it 'keeps the open tail apart from the finished prose until the end' do
    stream = described_class.new
    done = p::Prose.new(markup: 'Keep it <b>cold</b>.')
    assert_equal [done, p::Prose.new(markup: 'Or fre')], stream.append("Keep it **cold**.\n\nOr fre")
    assert_equal [done, p::Prose.new(markup: 'Or freeze it.')], stream.append("eze it.\n")
    assert_equal [p::Prose.new(markup: "Keep it <b>cold</b>.\n\nOr freeze it.")], stream.finish
  end

  it 'resolves a reference link a block from its definition only at the end' do
    stream = described_class.new
    parts = nil
    "See [the docs][1].\n\nMore.\n\n[1]: https://example.com\n".scan(/\s*\S+/).each { parts = stream.append(_1) }
    assert_equal [p::Prose.new(markup: "See [the docs][1].\n\nMore.")], Puri::Core::ReplyRenderer.merge(parts)
    assert_equal [p::Prose.new(markup: "See the docs.\n\nMore.")], stream.finish
  end

  it "lists the footnotes' text only at the end" do
    stream = described_class.new
    parts = nil
    "Ripe[^1].\n\n[^1]: USDA.\n\nMore.\n".scan(/\s*\S+/).each { parts = stream.append(_1) }
    assert_equal [p::Prose.new(markup: "Ripe<sup>1</sup>.\n\nMore.")], Puri::Core::ReplyRenderer.merge(parts)
    rule = Puri::Core::ReplyRenderer::RULE
    assert_equal [p::Prose.new(markup: "Ripe<sup>1</sup>.\n\nMore.\n\n#{rule}\n<sup>1</sup> USDA.")], stream.finish
  end

  it 'takes a different final text over the streamed one' do
    stream = described_class.new
    stream.append("Old.\n\nText.\n")
    assert_equal [p::Prose.new(markup: 'New.')], stream.finish('New.')
  end
end
