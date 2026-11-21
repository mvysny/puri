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

  # What every request to OpenStreetMap's services and tile servers sends, whose terms want the
  # app named, with a contact. libshumate 1.6 still sends its own on tiles (`R_shumate`).
  #
  # @return [String]
  USER_AGENT = 'Puri (+https://github.com/mvysny/puri)'

  # Loads GTK4, libadwaita and libshumate, the map widget. Neither of the last two has a Ruby
  # package, so each comes through GObject Introspection, which is not a Zeitwerk-shaped file.
  # Safe to call twice.
  #
  # `require 'gtk4'` runs `gtk_init`, so `GDK_BACKEND` and the display must already be in the
  # environment.
  #
  # @return [void]
  # @raise [LoadError] when apt's `ruby-gtk4`, `gir1.2-adw-1` or `gir1.2-shumate-1.0` is missing
  def self.require_gtk
    add_apt_gem('gtk4', apt_gem_specs)
    require 'gtk4'
    introspect('Adw', '1')
    return if introspect('Shumate', '1.0')

    Shumate.set_user_agent(USER_AGENT)
  end

  # @param namespace [String] a typelib's, and the module it loads into
  # @param version [String]
  # @return [Boolean] whether it was loaded already
  # @raise [LoadError] when the typelib isn't installed: Ruby-GNOME's `RepositoryError` is one
  def self.introspect(namespace, version)
    return true if Object.const_defined?(namespace)

    GObjectIntrospection::Repository.default.require(namespace, version)
    GObjectIntrospection::Loader.load(namespace, Object.const_set(namespace, Module.new))
    false
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
  private_class_method :introspect, :add_apt_gem, :apt_gem_specs
end
