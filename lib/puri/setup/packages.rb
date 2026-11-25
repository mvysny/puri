# frozen_string_literal: true

require 'open3'

module Puri
  module Setup
    # The packages from Ubuntu's archive that Puri runs on, the install guide's `apt install` line:
    #
    #   Packages.new.missing                # => ["whisper.cpp", "rhythmbox"]
    #   Packages.new.check(terminal)        # => false, printing the `sudo apt install` line
    #
    # Only checked, never installed: that needs sudo, which the setup leaves to the user.
    #
    # Ruby's standard library only: `bin/setup` loads it before `bundle install`.
    class Packages
      # `spec/site_spec.rb` holds the install guide's line to it. `llama.cpp-tools`, not the
      # `llama.cpp` metapackage, which also recommends `-tools-extra` and `python3-gguf`; Vulkan,
      # the one GPU backend the archive has for AMD, Intel and NVIDIA alike (`R_llama_cpp_apt`).
      #
      # @return [Array<String>]
      LIST = %w[git ruby ruby-bundler ruby-dev build-essential ruby-gtk4 gir1.2-adw-1 gir1.2-shumate-1.0
                libgtk-4-bin ripgrep llama.cpp-tools libggml0-backend-vulkan whisper.cpp
                localsearch-extractor-office rhythmbox].freeze

      # @param list [Array<String>]
      # @param command [Array<String>] what runs `dpkg-query`; specs run a stand-in
      def initialize(list: LIST, command: %w[dpkg-query])
        @list = list
        @command = command
      end

      # @return [Array<String>] those of the list not installed, in its order
      # @raise [Errno::ENOENT] without `dpkg-query`: not Debian's kind of system
      def missing
        # dpkg-query fails for a package the archive lacks, and still prints the others.
        out, = Open3.capture3(*@command, '-W', '-f', '${Package} ${db:Status-Status}\n', *@list)
        installed = out.lines.filter_map do |line|
          name, status = line.split
          name if status == 'installed'
        end
        @list - installed
      end

      # @param terminal [Puri::Setup::Terminal]
      # @return [Boolean] whether every package is installed
      def check(terminal)
        gone = missing
        if gone.empty?
          terminal.done("The packages from Ubuntu's archive")
          return true
        end
        terminal.todo("Puri needs packages from Ubuntu's archive that aren't installed. Install them, then run " \
                      "bin/setup again:\n\n    sudo apt install #{gone.join(' ')}\n")
        false
      rescue Errno::ENOENT
        terminal.todo("There's no dpkg-query here: Puri's setup knows only Ubuntu's packages.")
        false
      end
    end
  end
end
