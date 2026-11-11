# frozen_string_literal: true

module Puri
  # The GTK4 UI: the widgets and {BackendClient}, nothing else. It holds no state beyond view
  # state, so it can be rewritten in Vala as its own process if the Ruby binding fails.
  #
  # Desktop never names Pikuri or {Core}; it reaches Core only through {BackendClient} and
  # {Protocol}. `spec/boundaries_spec.rb` holds it to that.
  module Desktop
  end
end
