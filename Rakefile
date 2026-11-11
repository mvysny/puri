# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

Dir.glob('tasks/*.rake').each { |r| load r }

# The one gate: what CI runs and what a contributor runs before pushing (`bundle exec rake`).
desc 'Full check: the spec suite, rubocop, the sord signatures and the design-doc tripwires'
task check: %i[spec rubocop sig design_tripwires]

task default: :check
