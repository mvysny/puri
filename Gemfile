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
# Cuts the streamed Markdown into final kramdown blocks, so a reply converts each block once. On
# its git master, as pikuri; Gemfile.lock pins the commit, `bundle update streaming-markdown-parser`
# moves it.
gem 'streaming-markdown-parser', git: 'https://github.com/mvysny/streaming-markdown-parser.git', branch: 'master'

# pikuri on its git master, as pikuri-tui and pikuri-web ride it: Core's confirmations need the
# unreleased `Confirmer::Redirected` and the textless `Rejected` (pikuri#12). Gemfile.lock pins
# the commit; `bundle update pikuri-core` moves it. One checkout for both, since every pikuri gem
# pins `pikuri-core = <exact version>` in lockstep.
git 'https://codeberg.org/mvysny/pikuri.git', branch: 'master' do
  gem 'pikuri-core'
  gem 'pikuri-workspace'
end

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
