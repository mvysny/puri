# frozen_string_literal: true

require 'open3'

module Puri
  module Setup
    # Puri's Ruby libraries, the Gemfile's, which Bundler fetches into the checkout:
    #
    #   Bundle.new(root: '/home/u/puri').check(terminal)   # => true once `bundle check` passes
    #
    # Missing, they are installed once the user says yes, into `vendor/bundle` unless Bundler
    # already has a path, as the install guide's `bundle config set --local path` sets it.
    #
    # Ruby's standard library only: `bin/setup` loads it before `bundle install`.
    class Bundle
      # @param root [String] the checkout, which holds the Gemfile
      def initialize(root:)
        @root = root
        @env = { 'BUNDLE_GEMFILE' => File.join(root, 'Gemfile') }
      end

      # @param terminal [Puri::Setup::Terminal]
      # @return [Boolean] whether the bundle is complete now
      def check(terminal)
        if bundle?('check')
          terminal.done("Puri's Ruby libraries")
          return true
        end
        question = "Puri's Ruby libraries aren't installed. Fetch them with Bundler, from rubygems.org and " \
                   "GitHub, into #{Terminal.tilde(@root)}/vendor/bundle? A few compile some C, which takes a minute."
        unless terminal.ask?(question)
          terminal.todo("Puri's Ruby libraries aren't installed: bundle install, in #{Terminal.tilde(@root)}, " \
                        'installs them.')
          return false
        end
        bundle?('config', 'set', '--local', 'path', 'vendor/bundle') unless path?
        if system(@env, 'bundle', 'install', chdir: @root) && bundle?('check')
          terminal.done("Puri's Ruby libraries")
          return true
        end
        terminal.todo("bundle install failed, above. Run bin/setup again once it's fixed.")
        false
      end

      private

      # @param args [Array<String>]
      # @return [Boolean] whether `bundle` succeeded, quietly
      def bundle?(*args)
        system(@env, 'bundle', *args, chdir: @root, out: File::NULL, err: File::NULL) || false
      end

      # @return [Boolean] whether Bundler has a path to install into, from any of its settings
      def path?
        out, status = Open3.capture2(@env, 'bundle', 'config', 'get', '--parseable', 'path', chdir: @root)
        status.success? && out.start_with?('path=')
      end
    end
  end
end
