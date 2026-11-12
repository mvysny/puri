# frozen_string_literal: true

require 'open3'
require 'rbconfig'

# The split between Core and Desktop, held by checks because Ruby has no package-private code.
# Under Zeitwerk every dependency between our files is a constant name, so grep sees them all;
# comment lines are skipped, since the namespaces' docs name the rule they keep.
RSpec.describe 'namespace boundaries' do
  gui = /\b(Gtk|Adw|GLib|Gio|Gdk|GObject\w*)::|Puri::Desktop|\bDesktop::/
  forbidden = {
    'lib/puri/core' => gui,
    'lib/puri/protocol' => Regexp.union(gui, /Pikuri|Puri::Core|\bCore::/),
    'lib/puri/desktop' => /Pikuri|Puri::Core|\bCore::/,
    'dev/puri/dummy' => gui
  }

  forbidden.each do |dir, pattern|
    it "#{dir} names nothing across its boundary" do
      files = Dir.glob("#{dir}{.rb,/**/*.rb}", base: File.expand_path('..', __dir__))
      refute_empty files
      offenders = files.flat_map do |file|
        lines = File.readlines(File.expand_path("../#{file}", __dir__), encoding: 'UTF-8')
        lines.each_with_index.filter_map do |line, i|
          "#{file}:#{i + 1}: #{line.strip}" if line.match?(pattern) && !line.lstrip.start_with?('#')
        end
      end
      assert_empty offenders
    end
  end

  # What grep can't see: a gem that drags GTK in. A fresh process, since this one may have
  # loaded GTK for the Desktop specs.
  it 'loads Core, Protocol and the dummy without GTK' do
    script = <<~RUBY
      require 'puri'
      require 'puri/dummy'
      Puri::LOADER.eager_load_namespace(Puri::Core)
      Puri::LOADER.eager_load_namespace(Puri::Protocol)
      abort 'GTK got loaded' if defined?(::Gtk) || defined?(::GLib)
      print Puri::Core::PikuriCore.name, ' ', Puri::Dummy::Backend.name
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__),
                                      '-I', File.expand_path('../dev', __dir__), '-e', script)
    assert status.success?, err
    assert_equal 'Puri::Core::PikuriCore Puri::Dummy::Backend', out
  end
end
