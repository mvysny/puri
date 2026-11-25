# frozen_string_literal: true

require 'puri'

module Puri
  # The model eval of `design/ideas/model-eval.md`: the tasks run through Puri's own Core, its
  # prompts and tools, against pikuri's demo world, once per configuration, and the deterministic
  # checks grade each run. Development only, like {Dummy}: it loads only with `dev/` on the load
  # path, as `rake eval` puts it.
  #
  #   DISPLAY=:99 DISABLE_WAYLAND=1 rake eval    # every configuration, every task, 3 runs each
  #   rake eval CONFIGS='Qwen3.5-4B' TASKS=thursday,rain REPEATS=1
  #   rake eval:report                           # today's report again, from its results
  #
  # The world is pikuri's: `dev/demo-home/` and the Thunderbird testbed, built today, and a
  # testbed session on its own display for the hand-offs (`Eval::World`).
  module Eval
    # @return [String] where each day's results go, one folder per day
    STATE = File.join(ENV['XDG_STATE_HOME'].to_s.empty? ? File.expand_path('~/.local/state') : ENV['XDG_STATE_HOME'],
                      'puri', 'eval')
  end
end

require_relative 'eval/matcher'
require_relative 'eval/recorder'
require_relative 'eval/box'
require_relative 'eval/lemonade'
require_relative 'eval/world'
require_relative 'eval/task'
require_relative 'eval/grader'
require_relative 'eval/runner'
require_relative 'eval/report'
