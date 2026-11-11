# frozen_string_literal: true

# The bash script is the one implementation; this task only puts it in `rake check`.
desc 'Design docs: cited slugs resolve, headings and caps hold, CLAUDE.md is a symlink'
task :design_tripwires do
  sh 'design/verify_design_tripwires.sh'
end
