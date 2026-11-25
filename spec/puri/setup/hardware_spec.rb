# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Puri::Setup::Hardware do
  # @param description [String]
  # @param mib [Integer]
  # @return [Puri::Setup::Hardware::Gpu]
  def gpu(description, mib) = described_class::Gpu.new(name: 'Vulkan0', description:, mib:)

  describe '.parse' do
    it "reads llama.cpp's devices, its log lines around them, and skips a software one" do
      output = <<~OUT
        ggml_vulkan: Found 2 Vulkan devices:
        Available devices:
          Vulkan0: AMD Radeon 890M Graphics (RADV STRIX1) (32768 MiB, 31000 MiB free)
          Vulkan1: llvmpipe (LLVM 20.1.2, 256 bits) (7262 MiB, 7262 MiB free)
      OUT
      assert_equal [gpu('AMD Radeon 890M Graphics (RADV STRIX1)', 32_768)], described_class.parse(output)
    end

    it 'finds none where there is none' do
      assert_empty described_class.parse("Available devices:\n  (none)\n")
    end
  end

  describe '.probe' do
    it "runs llama-server, and rounds the RAM up as it's sold" do
      Dir.mktmpdir do |dir|
        File.write(meminfo = File.join(dir, 'meminfo'), "MemTotal:        7436308 kB\nMemFree: 1 kB\n")
        File.write(cmdline = File.join(dir, 'cmdline'), "BOOT_IMAGE=/vmlinuz quiet ttm.pages_limit=12582912\n")
        command = ['sh', '-c',
                   'echo "Available devices:"; echo "  Vulkan0: NVIDIA GeForce RTX 4060 (8188 MiB, 7000 MiB free)"']
        hardware = described_class.probe(command:, meminfo:, cmdline:)
        assert_equal [gpu('NVIDIA GeForce RTX 4060', 8188)], hardware.gpus
        assert_equal 8, hardware.ram_gb
        assert hardware.ttm
      end
    end
  end

  describe 'Ornith' do
    it 'fits a card or integrated graphics with the memory for it' do
      assert described_class.new(gpus: [gpu('NVIDIA GeForce RTX 5090', 32_607)], ram_gb: 32).ornith?
      refute described_class.new(gpus: [gpu('NVIDIA GeForce RTX 4060', 8188)], ram_gb: 64).ornith?
      refute described_class.new(gpus: [], ram_gb: 128).gpu?
    end

    it "lends integrated Radeon graphics the RAM but the desktop's, where there's enough of it" do
      igpu = gpu('AMD Radeon 890M Graphics (RADV STRIX1)', 16_384)
      assert_equal 48, described_class.new(gpus: [igpu], ram_gb: 64).ornith_share
      assert_nil described_class.new(gpus: [igpu], ram_gb: 32).ornith_share
      assert_nil described_class.new(gpus: [gpu('AMD Radeon RX 7900 XTX (RADV NAVI31)', 24_560)],
                                     ram_gb: 64).ornith_share
      assert_equal 'ttm.pages_limit=12582912 ttm.page_pool_size=12582912', described_class.ttm_options(48)
    end

    it 'tells integrated Radeon graphics from cards by their names' do
      ['AMD Radeon Graphics (RADV REMBRANDT)', 'AMD Radeon 780M Graphics (RADV PHOENIX)',
       'AMD Radeon 8060S Graphics (RADV GFX1151)', 'AMD Radeon Vega 8 Graphics (RADV RAVEN)'].each do
        assert gpu(_1, 1).integrated_radeon?, _1
      end
      ['AMD Radeon RX 7600 (RADV NAVI33)', 'AMD Radeon PRO W7900 (RADV NAVI31)', 'Intel(R) Graphics (ARL)'].each do
        refute gpu(_1, 1).integrated_radeon?, _1
      end
    end
  end
end
