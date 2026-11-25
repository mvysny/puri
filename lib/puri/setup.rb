# frozen_string_literal: true

module Puri
  # `bin/setup`, the one command that installs Puri and, run again, is its doctor: each check in
  # the install guide's order, a fix for each that needs no sudo once the user says yes, and the
  # rest printed for the user to do.
  #
  #   ✓ The packages from Ubuntu's archive          {Packages}, then stop if any is missing
  #   ✓ Puri's Ruby libraries                       {Bundle}: `bundle install`
  #   ✓ Puri is on your desktop: Super+Alt+Space    {Install}, what `rake install` writes
  #   ✓ The config, ~/.config/puri/config.toml      written only when there is none
  #   ✓ The model, ggml-org/Qwen3.5-4B-GGUF:Q4_K_M  {HubDownload}, after {Hardware}'s warning
  #   ✗ Thunderbird's global search is off: …       {Calendars} too, printed as where to click
  #   ✓ Your documents, ~/Documents, are indexed    {SearchLocations}, {FileIndex}
  #
  # Two processes: `bin/setup` runs the first two on Ruby's standard library alone, since the
  # gems are one of its fixes, then hands over to {Doctor} under the bundle. The checks never
  # write the config but when it is missing, and never run sudo.
  module Setup
  end
end
