# frozen_string_literal: true

module Puri
  module Protocol
    # What a conversation's status bar shows: the model its next turn runs on, and how full its
    # context is, each worded by Core.
    #
    #   Status.new(model: 'Ornith 1.5', context: '7.4k of 64.0k tokens', fill: 0.12,
    #              detail: 'msg #2  Δ+1.6k  ↑1.0k  ↓0.6k')
    #   Status.new(model: 'Ornith 1.5')   # nothing measured, the window unknown
    #
    # @!attribute [r] model
    #   @return [String] a {Models#names} entry, the connection the next turn uses
    # @!attribute [r] context
    #   @return [String] the context used, against the window when known; empty when neither is
    # @!attribute [r] fill
    #   @return [Float, nil] the share of the window used, 0.0 to 1.0; nil while the window or
    #     the use is unknown
    # @!attribute [r] detail
    #   @return [String] the latest reply's tokens; empty before the first
    class Status < Data.define(:model, :context, :fill, :detail)
      # @param model [String]
      # @param context [String]
      # @param fill [Float, nil]
      # @param detail [String]
      def initialize(model:, context: '', fill: nil, detail: '') = super
    end
  end
end
