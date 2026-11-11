# frozen_string_literal: true

module Puri
  module Protocol
    # Part of a {Reply}: a run of paragraphs, headings and lists, as one piece of Pango markup,
    # so a selection can span them. Core escaped every character the model wrote.
    #
    # @!attribute [r] markup
    #   @return [String] Pango markup, `"<b>Fridge</b>: 3–5 days\n\n• cut side down"`
    class Prose < Data.define(:markup)
    end
  end
end
