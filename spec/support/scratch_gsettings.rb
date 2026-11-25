# frozen_string_literal: true

require 'fileutils'
require 'open3'

# gsettings on a scratch keyfile, for a spec that reads or writes settings, with localsearch's
# schema, cut down to the one key the setup touches, compiled beside it: CI has no localsearch,
# and a spec must never touch the desktop's own settings.
#
#   env = ScratchGSettings.env(home)   # => GSETTINGS_BACKEND, GSETTINGS_SCHEMA_DIR, XDG_CONFIG_HOME
#   ScratchGSettings.around(home) { … }   # the same, in this process's ENV for the block
module ScratchGSettings
  # @return [String]
  TRACKER = <<~XML
    <schemalist>
      <schema id="org.freedesktop.Tracker3.Miner.Files" path="/org/freedesktop/tracker/miner/files/">
        <key name="index-recursive-directories" type="as">
          <default>['&amp;DESKTOP', '&amp;DOCUMENTS', '&amp;MUSIC', '&amp;PICTURES', '&amp;VIDEOS']</default>
        </key>
      </schema>
    </schemalist>
  XML

  # @param home [String] a scratch folder
  # @return [Hash{String => String}] what makes gsettings use it
  def self.env(home)
    schemas = File.join(home, 'schemas')
    unless File.file?(File.join(schemas, 'gschemas.compiled'))
      FileUtils.mkdir_p(schemas)
      File.write(File.join(schemas, 'org.freedesktop.Tracker3.Miner.Files.gschema.xml'), TRACKER)
      _, err, status = Open3.capture3('glib-compile-schemas', schemas)
      raise "glib-compile-schemas failed: #{err}" unless status.success?
    end
    { 'GSETTINGS_BACKEND' => 'keyfile', 'GSETTINGS_SCHEMA_DIR' => schemas,
      'XDG_CONFIG_HOME' => File.join(home, 'config') }
  end

  # @param home [String]
  # @return [Object] the block's
  def self.around(home)
    vars = env(home)
    saved = ENV.to_h.slice(*vars.keys)
    ENV.update(vars)
    yield
  ensure
    vars&.each_key { saved.key?(_1) ? ENV[_1] = saved[_1] : ENV.delete(_1) }
  end
end
