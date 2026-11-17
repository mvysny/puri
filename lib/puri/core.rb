# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'pikuri-core'
require 'pikuri-html'
require 'pikuri-thunderbird'
require 'pikuri-web'
require 'pikuri-workspace'
require 'pikuri-conversations'
require 'pikuri-os'

module Puri
  # The backend. It takes {Protocol} commands and emits {Protocol} events on its own threads.
  #
  # Core never names Gtk, Adw, GLib, Gio or {Desktop}, so it loads and runs without GTK and could
  # move into its own process unchanged; `spec/boundaries_spec.rb` holds it to that.
  module Core
  end
end
