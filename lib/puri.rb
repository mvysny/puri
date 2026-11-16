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
    add_apt_gem('gtk4', apt_gem_specs)
    require 'gtk4'
    return if Object.const_defined?(:Adw)

    GObjectIntrospection::Repository.default.require('Adw', '1')
    GObjectIntrospection::Loader.load('Adw', Object.const_set(:Adw, Module.new))
  end

  # Appends apt's +name+ gem and its runtime dependencies to the load path, so Bundler, which hides
  # every gem not in the lockfile, can't hide them.
  #
  # Only the gem layout needs it: Ubuntu 26.10's ruby-cairo installs into
  # `/usr/lib/*/rubygems-integration/` and is otherwise unreachable, while a package still in
  # `vendor_ruby` has nothing at its gemspec's paths and adds nothing. Appended, so a bundled gem of
  # the same name still wins.
  #
  # @param name [String] the gem, e.g. `gtk4`
  # @param specs [Hash{String => Gem::Specification}] from {apt_gem_specs}
  # @param seen [Array<String>] the gems already visited
  # @return [void]
  def self.add_apt_gem(name, specs, seen = [])
    spec = specs[name]
    return if spec.nil? || seen.include?(name)

    seen << name
    spec.full_require_paths.each do |dir|
      $LOAD_PATH << dir if File.directory?(dir) && !$LOAD_PATH.include?(dir)
    end
    spec.runtime_dependencies.each { |dep| add_apt_gem(dep.name, specs, seen) }
  end

  # Under Bundler `Gem.path` is the bundle alone, but `Gem.default_path` still lists apt's folders.
  #
  # @return [Hash{String => Gem::Specification}] apt's newest gemspec of each name
  def self.apt_gem_specs
    Gem.default_path.grep(/rubygems-integration/)
       .flat_map { |dir| Dir[File.join(dir, 'specifications', '*.gemspec')] }
       .filter_map { |file| Gem::Specification.load(file) }
       .group_by(&:name).transform_values { |all| all.max_by(&:version) }
  end
  private_class_method :add_apt_gem, :apt_gem_specs
end
