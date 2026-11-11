# frozen_string_literal: true

require_relative 'support/broadway'

# For specs that build widgets: a Broadway display, GTK and Adw, the whole app loaded, and one
# registered application for windows to belong to. Specs drive the widget tree directly and spin
# the main loop with {GtkHelpers#wait_until}; no browser is attached, so nothing is painted.
Broadway.start
# ruby-gnome 4.3.4 runs a signal handler inside the GC when freeing a widget's wrapper disposes the
# widget (`row-selected` from a dropped HistorySidebar's ListBox): Ruby aborts with `[BUG] object
# allocation during garbage collection phase`. Specs drop a window per example; the app never does.
# https://github.com/ruby-gnome/ruby-gnome/issues/1754
GC.disable
Puri.require_gtk
Puri::LOADER.eager_load

# Non-unique, so a running Puri never swallows it.
GTK_APP = Adw::Application.new('io.github.mvysny.Puri.Spec', :non_unique)
GTK_APP.register(nil) or raise 'the spec application failed to register'

# Main-loop helpers for widget specs.
module GtkHelpers
  # Spins the GTK main loop until the block is truthy, the way a running app would between events.
  #
  # @param timeout [Float] seconds before it fails
  # @param message [String] what was awaited, for the failure
  # @return [void]
  def wait_until(message, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "timed out after #{timeout} s waiting until #{message}"
      end

      GLib::MainContext.default.iteration(false) || sleep(0.01)
    end
  end
end

RSpec.configure { |config| config.include GtkHelpers }
