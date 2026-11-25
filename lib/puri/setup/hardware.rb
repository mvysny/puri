# frozen_string_literal: true

require 'open3'

module Puri
  module Setup
    # What the model would run on here, as llama.cpp sees it, for the setup's two words of advice:
    # a warning where there's no GPU, and where Ornith fits, the hint that it does
    # (`docs/models.html`, "Which computer runs which").
    #
    #   hardware = Hardware.probe
    #   hardware.gpu?             # => false: the model runs on the processor alone
    #   hardware.ornith?          # => true where a GPU has the memory for Ornith
    #   hardware.ornith_share     # => 48, the GB integrated Radeon graphics may be lent for it, or nil
    #
    # A GPU is a device `llama-server --list-devices` lists (`R_llama_list_devices`), never a
    # software one such as Mesa's lavapipe, which runs on the processor too.
    #
    # Immutable.
    class Hardware
      # One device llama.cpp runs a model on, as `--list-devices` prints it:
      #
      #   Vulkan0: AMD Radeon 890M Graphics (RADV STRIX1) (32768 MiB, 31000 MiB free)
      #
      # @!attribute [r] name
      #   @return [String] `Vulkan0`
      # @!attribute [r] description
      #   @return [String] `AMD Radeon 890M Graphics (RADV STRIX1)`
      # @!attribute [r] mib
      #   @return [Integer] its memory in all, in MiB: an integrated GPU's share of the RAM
      class Gpu < Data.define(:name, :description, :mib)
        # @return [Boolean] whether it is AMD graphics built into the processor, whose share of the
        #   RAM the kernel's `ttm` options set: "AMD Radeon 890M Graphics", "AMD Radeon Graphics",
        #   never a card's "AMD Radeon RX 7900 XTX"
        def integrated_radeon? = description.match?(/\bRadeon(?:\(TM\))?(?: Vega \d+| \d{3,4}[MS])? Graphics\b/)
      end

      # @return [Integer] MiB a GPU needs for Ornith 1.5 at Puri's 64K context, "about 32 GB" with
      #   a card's own reporting a little under it
      ORNITH_MIB = 30 * 1024

      # @return [Integer] GB of RAM a computer needs before its integrated graphics run Ornith
      ORNITH_RAM_GB = 48

      # @return [Integer] GB the desktop keeps for itself when the graphics are lent the rest
      DESKTOP_GB = 16

      # @return [Regexp] devices that are the processor in disguise
      SOFTWARE = /llvmpipe|lavapipe|softpipe|swiftshader/i

      # @return [Array<Puri::Setup::Hardware::Gpu>] never a software device
      attr_reader :gpus

      # @return [Integer] GB of RAM, rounded up to the next 8 as it is sold: `MemTotal` misses
      #   what the firmware keeps
      attr_reader :ram_gb

      # @return [Boolean] whether the kernel's command line sets `ttm.pages_limit` already
      attr_reader :ttm

      # @param command [Array<String>] what runs `llama-server`; specs run a stand-in
      # @param meminfo [String]
      # @param cmdline [String]
      # @return [Puri::Setup::Hardware]
      def self.probe(command: %w[llama-server], meminfo: '/proc/meminfo', cmdline: '/proc/cmdline')
        out, = Open3.capture2e(*command, '--list-devices')
        kib = File.read(meminfo)[/^MemTotal:\s+(\d+) kB/, 1].to_i
        new(gpus: parse(out), ram_gb: (kib / (1024.0 * 1024) / 8).ceil * 8,
            ttm: File.read(cmdline).include?('ttm.pages_limit='))
      end

      # @param output [String] `llama-server --list-devices`'s, log lines and all
      # @return [Array<Puri::Setup::Hardware::Gpu>]
      def self.parse(output)
        output.scan(/^\s+(\S+): (.+) \((\d+) MiB, \d+ MiB free\)$/).filter_map do |name, description, mib|
          Gpu.new(name:, description:, mib: mib.to_i) unless description.match?(SOFTWARE)
        end
      end

      # @param gpus [Array<Puri::Setup::Hardware::Gpu>]
      # @param ram_gb [Integer]
      # @param ttm [Boolean]
      def initialize(gpus:, ram_gb:, ttm: false)
        @gpus = gpus.freeze
        @ram_gb = ram_gb
        @ttm = ttm
        freeze
      end

      # @return [Boolean] whether the model runs on anything but the processor
      def gpu? = @gpus.any?

      # @return [Boolean] whether a GPU has the memory to hold Ornith
      def ornith? = @gpus.any? { _1.mib >= ORNITH_MIB }

      # @return [Integer, nil] the GB integrated Radeon graphics would need lent before they run
      #   Ornith, the rest of the RAM bar the desktop's; nil when they hold it already, when there's
      #   too little RAM, or no such graphics
      def ornith_share
        return nil if ornith? || @ram_gb < ORNITH_RAM_GB || @gpus.none?(&:integrated_radeon?)

        @ram_gb - DESKTOP_GB
      end

      # @param gigabytes [Integer]
      # @return [String] the kernel options that lend AMD's graphics that much RAM, as
      #   `docs/models.html` has them: 4 KiB pages
      def self.ttm_options(gigabytes)
        pages = gigabytes * 262_144
        "ttm.pages_limit=#{pages} ttm.page_pool_size=#{pages}"
      end
    end
  end
end
