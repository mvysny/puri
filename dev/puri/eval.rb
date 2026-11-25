# frozen_string_literal: true

require 'puri'

module Puri
  # The model eval: the tasks run through Puri's own Core, its prompts and tools, against
  # pikuri's demo world, once per configuration, and the deterministic checks grade each run.
  # What it found is `R_model_eval`. Development only, like {Dummy}: it loads only with `dev/` on
  # the load path, as `rake eval` puts it.
  #
  #   DISPLAY=:99 DISABLE_WAYLAND=1 rake eval    # every configuration, every task, 3 runs each
  #   rake eval CONFIGS='Qwen3.5-4B' TASKS=thursday,rain REPEATS=1
  #   rake eval:report                           # today's report again, from its results
  #
  # The world is pikuri's, built the same day ({World#guard!} checks), so before a day's run,
  # from pikuri's checkout:
  #
  #   pikuri-thunderbird/dev/testbed/session stop      # yesterday's, if it runs: the build refuses
  #   pikuri-thunderbird/dev/testbed/build             # the Thunderbird profile, and ~/Documents
  #   systemctl --user restart localsearch-3           # else the index knows none of the new files
  #   DISABLE_WAYLAND=1 pikuri-thunderbird/dev/testbed/session start --display   # prints DISPLAY
  #
  # The box is the server of the first `[[llm]]` in Puri's own config: llama.cpp's router with
  # `eval/presets.ini`, nothing else using it all day, Puri included. A configuration's 105 runs take one to two
  # hours on a Radeon 890M, thinking.
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
