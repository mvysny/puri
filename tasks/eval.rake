# frozen_string_literal: true

# The model eval (design/ideas/model-eval.md), a dev-only mode: dev/puri/eval.rb says what it
# needs running first. Results go to ~/.local/state/puri/eval/<today>/, never into the repo.
#
#   DISPLAY=:99 DISABLE_WAYLAND=1 rake eval     # every configuration, every task, 3 runs each
#   rake eval CONFIGS='Qwen3.5-4B;Granite-4.2-3B' TASKS=thursday,rain REPEATS=1
#   rake eval:report                            # today's report.md again
#
# DISPLAY is the testbed session's, and both are needed from the start: the hand-offs spawn
# Thunderbird on the environment the process started with. PIKURI names pikuri's source
# checkout, ~/work/my/pikuri by default: the demo world's facts and the testbed's session live
# there.

# @return [String] today's results folder
def eval_day_dir
  require 'date'
  File.join(Puri::Eval::STATE, Date.today.iso8601)
end

# @return [void]
def eval_load
  $LOAD_PATH.unshift File.expand_path('../lib', __dir__), File.expand_path('../dev', __dir__)
  require 'puri/eval'
end

desc 'The model eval: CONFIGS, TASKS and REPEATS narrow it'
task :eval do
  eval_load
  world = Puri::Eval::World.new(pikuri: ENV.fetch('PIKURI', '~/work/my/pikuri'), documents: '~/Documents')
  configs = Puri::Eval::Runner::CONFIGURATIONS
  configs = configs.select { ENV['CONFIGS'].split(';').include?(_1.name) } if ENV['CONFIGS']
  tasks = Puri::Eval::Task.load(world.facts)
  tasks = tasks.select { ENV['TASKS'].split(',').include?(_1.id) } if ENV['TASKS']
  Puri::Eval::Runner.new(configurations: configs, tasks:, repeats: Integer(ENV.fetch('REPEATS', '3')), world:,
                         day_dir: eval_day_dir).run
  puts "Report: #{Puri::Eval::Report.new(eval_day_dir).write}"
end

namespace :eval do
  desc "Today's model eval report, from its results"
  task :report do
    eval_load
    puts Puri::Eval::Report.new(eval_day_dir).write
  end
end
