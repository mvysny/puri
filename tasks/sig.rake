# frozen_string_literal: true

# Types are written once, as YARD tags in lib/; sord compiles them into sig/puri.rbs, which is
# committed but never edited by hand. `rake check` runs `sig`, and CI fails when the regenerated
# file differs from the committed one.
#
# There's no `sig:validate`: `rbs validate` would have to resolve every Gtk::, Adw::, GLib:: and
# Zeitwerk:: name, and none of them ships a sig/.

SIG_FILE = 'sig/puri.rbs'

# sord sees only this project, so it warns "wasn't able to be resolved to a constant" for every
# Gtk:: / Adw:: / stdlib name and writes it through unchanged. A warning passes only when Ruby,
# with GTK, Adw and the whole app loaded, resolves the name from the top level; a bare name that
# relies on lexical scope still fails. Loading GTK needs a display, so this starts a Broadway one.
#
# @param line [String] one line of sord's output, ANSI-stripped
# @return [Boolean] true for an unresolved-constant warning about a name Ruby knows
def sig_outside_constant?(line)
  name = line[/\) \S+: (\S+) wasn't able to be resolved to a constant in this project$/, 1]
  return false unless name

  @sig_app_loaded ||= begin
    require_relative '../spec/support/broadway'
    $LOAD_PATH.unshift File.expand_path('../lib', __dir__)
    require 'puri'
    Broadway.start
    Puri.require_gtk
    Puri::LOADER.eager_load
    true
  end
  Object.const_defined?(name)
end

namespace :sig do
  desc "Regenerate #{SIG_FILE} from the YARD tags via sord; fails on any sord warning"
  task :generate do
    require 'English'
    rm_rf '.yardoc'
    mkdir_p 'sig'
    out = `bundle exec sord gen #{SIG_FILE} --rbs --regenerate --no-sord-comments 2>&1`
          .gsub(/\e\[[0-9;]*m/, '')
    print out
    raise 'sord exited non-zero' unless $CHILD_STATUS.success?

    # Per-object lines only: the closing "There were N important warnings" repeats them.
    offenders = out.lines.grep(/^\[(OMIT|INFER|WARN|ERROR)\s*\] \(/).reject { |l| sig_outside_constant?(l) } +
                out.lines.grep(/^Parlour warning/)
    raise "sord emitted #{offenders.size} warning(s):\n#{offenders.join}" unless offenders.empty?
  end
end

desc "Regenerate #{SIG_FILE} (sig:generate)"
task sig: 'sig:generate'
