# frozen_string_literal: true

# `bin/setup` on a fresh Ubuntu 26.04 in podman, as a new user runs the install guide's
# Super-quick path; dev/puri/fresh_install.rb has what it sets up and what it expects.
#
#   rake fresh_install              # this checkout's HEAD; the models' 3.5 GB declined
#   rake fresh_install MODELS=1     # downloads them too, and expects "Puri is ready"
#   rake fresh_install REPO=https://github.com/mvysny/puri   # what the guide clones
#   rake fresh_install FRESH=1      # the image anew, from today's archive
#   rake fresh_install KEEP=1       # leaves the container, to look around in

desc 'bin/setup on a fresh Ubuntu 26.04 in podman; MODELS=1, REPO=url, FRESH=1, KEEP=1'
task :fresh_install do
  $LOAD_PATH.unshift File.expand_path('../lib', __dir__), File.expand_path('../dev', __dir__)
  require 'puri/fresh_install'
  failures = Puri::FreshInstall.new(models: ENV['MODELS'] == '1', repo: ENV.fetch('REPO', nil),
                                    fresh: ENV['FRESH'] == '1', keep: ENV['KEEP'] == '1').run
  abort "\nbin/setup on a fresh Ubuntu went wrong:\n#{failures.map { "  #{_1}\n" }.join}" unless failures.empty?
  puts "\nbin/setup installed Puri on a fresh Ubuntu 26.04#{', the models too' if ENV['MODELS'] == '1'}."
end
