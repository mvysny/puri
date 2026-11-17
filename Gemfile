# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.3'

# GTK4 and libadwaita are deliberately absent: they come from apt (`ruby-gtk4`, `gir1.2-adw-1`),
# and `require 'gtk4'` finds apt's copy under `bundle exec` anyway. Listed here, Bundler would
# compile the whole Ruby-GNOME stack from source (AGENTS.md, Conventions).

# One loader at lib/, eager-loaded at boot: a dependency between our files is a constant name.
gem 'zeitwerk', '~> 2.8'

# Core renders the model's Markdown into Pango markup, as pikuri-web renders it into HTML; GFM
# input, since LLMs write backtick fences and pipe tables.
gem 'kramdown', '~> 2.5'
gem 'kramdown-parser-gfm', '~> 1.1'
# Cuts the streamed Markdown into final kramdown blocks, so a reply converts each block once.
gem 'streaming-markdown-parser', '~> 0.1'

# pikuri on its git master, as pikuri-tui and pikuri-web ride it: Core's confirmations need the
# unreleased `Confirmer::Redirected` and the textless `Rejected` (pikuri#12). Gemfile.lock pins
# the commit; `bundle update pikuri-core` moves it. One checkout for both, since every pikuri gem
# pins `pikuri-core = <exact version>` in lockstep. pikuri-web brings `web_search` and
# `web_read_cached`, and with them nokogiri; pikuri-html registers the HTML → Markdown extractor.
# pikuri-thunderbird reads the local Thunderbird profile's mail, contacts and calendar, and hands a
# drafted mail or event to Thunderbird's own UI; it brings sqlite3 and mail (parse-only).
# pikuri-pdf is the PDF extractor for a machine with no container runtime (`D_extractors`); it
# brings pdf-reader, pure Ruby.
git 'https://codeberg.org/mvysny/pikuri.git', branch: 'master' do
  gem 'pikuri-core'
  gem 'pikuri-html'
  gem 'pikuri-pdf'
  gem 'pikuri-thunderbird'
  gem 'pikuri-web'
  gem 'pikuri-workspace'
end

# The conversations Core hosts: their agents and turns, the folder they are saved in, the titler
# and the per-server request throttle. A workshop gem, on its git master like pikuri;
# `bundle update pikuri-conversations` moves the pin. pikuri-os brings `fileindex_search` and
# `fileindex_read` over the desktop's own file index (GNOME's localsearch, or recoll), which
# already holds the PDFs' and office files' text; it drags in pikuri-code, whose bash Puri
# doesn't wire. pikuri-extractors converts office files and PDFs in a networkless container, the
# extractor wired when podman or docker is installed (`D_extractors`); it brings no gem.
git 'https://github.com/mvysny/pikuri-workshop.git', branch: 'master' do
  gem 'pikuri-conversations'
  gem 'pikuri-extractors'
  gem 'pikuri-os'
end

# Core::Config, ported from pikuri-web with its gems: tomlrb parses the TOML (pure Ruby, MIT, no
# dependencies; toml-rb drags in the unlicensed, abandoned citrus), typemap maps it onto the
# config's Data classes, checking every value against its YARD type. typemap reads those types
# from sig/puri.rbs through rbs's parser, which makes rbs a runtime gem (~0.2 s of `require`).
gem 'rbs', '~> 4.2'
gem 'tomlrb', '~> 3.0'
gem 'typemap', '~> 0.1'

# Types are written once, as YARD tags; sord compiles them into the committed sig/puri.rbs, and
# `rake sig` fails on any tag sord cannot type. redcarpet renders the Markdown .yardopts selects.
group :development do
  gem 'rake', '~> 13.4'
  gem 'redcarpet', '~> 3.6'
  gem 'rubocop', '~> 1.92', require: false
  gem 'sord', '~> 7.1', require: false
  gem 'yard', '~> 0.9.45'

  # rubocop's parser. sord reads every bundled gem's rbi/, and parlour 9.1.2 (the latest, under
  # sord 7.1) can't parse prism 2's ("node after a sig must be a method definition").
  gem 'prism', '< 2', require: false
end

# rspec-core's structure with minitest's asserts; no rspec-expectations, no rspec-mocks.
group :test do
  gem 'minitest', '~> 6.0'
  gem 'rspec-core', '~> 3.13'
  gem 'simplecov', '~> 0.22', require: false
end
