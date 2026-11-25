# frozen_string_literal: true

# `Puri::Setup::Install` from the command line, as the install guide and `bin/setup` run it. The
# shortcut is Super+Alt+Space unless `HOTKEY` names another (`HOTKEY='<Super>p'`) or none
# (`HOTKEY=`); `AUTOSTART=1` also starts Puri hidden at login.

# @return [Puri::Setup::Install]
def install_setup
  $LOAD_PATH.unshift File.expand_path('../lib', __dir__)
  require 'puri'
  Puri::Setup::Install.new
end

desc "Install Puri for this user, run from this checkout; HOTKEY='<Super>p' (default Super+Alt+Space), AUTOSTART=1"
task :install do
  install = install_setup
  hotkey = Puri::Setup::Install.hotkey(ENV.fetch('HOTKEY', Puri::Setup::Install::DEFAULT_HOTKEY))
  install.write(hotkey:, autostart: ENV['AUTOSTART'] == '1').each { puts "wrote #{_1}" }
  puts hotkey ? "#{hotkey} opens Puri" : "No shortcut bound; bind one to: gapplication launch #{Puri::Setup::Install::APP_ID}"
end

desc 'Remove what `rake install` wrote'
task :uninstall do
  install_setup.remove
end
