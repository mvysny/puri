# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'zeitwerk'

# A Siri-style desktop assistant on pikuri. Three namespaces share one loader: {Puri::Core}, the
# backend; {Puri::Protocol}, the messages between the two; {Puri::Desktop}, the GTK4 UI. Only
# `exe/puri` knows both sides.
#
# Requiring this file sets the loader up but loads nothing, so a process may load Core and
# Protocol without GTK. Desktop's windows subclass Adw's at load time, so whoever loads Desktop
# calls {require_gtk} first.
module Puri
  # @return [Zeitwerk::Loader] the one loader, rooted at lib/
  LOADER = Zeitwerk::Loader.for_gem
  LOADER.setup

  # Loads GTK4 and libadwaita. libadwaita has no Ruby package, so it comes through GObject
  # Introspection, which is not a Zeitwerk-shaped file. Safe to call twice.
  #
  # `require 'gtk4'` runs `gtk_init`, so `GDK_BACKEND` and the display must already be in the
  # environment.
  #
  # @return [void]
  def self.require_gtk
    require 'gtk4'
    return if Object.const_defined?(:Adw)

    GObjectIntrospection::Repository.default.require('Adw', '1')
    GObjectIntrospection::Loader.load('Adw', Object.const_set(:Adw, Module.new))
  end
end
