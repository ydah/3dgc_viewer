# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe ThreeDgcViewer::ShaderLoader do
  ShaderModule = Class.new do
    attr_reader :label, :release_count

    def initialize(label)
      @label = label
      @release_count = 0
    end

    def release
      @release_count += 1
    end
  end

  it "reads shaders from the configured shader directory" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.wgsl"), "shader source")
      loader = described_class.new(nil, shader_dir: dir)

      expect(loader.source("test.wgsl")).to eq("shader source")
    end
  end

  it "can disable and clear the shader source cache for development reloads" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.wgsl")
      File.write(path, "first")
      cached = described_class.new(nil, shader_dir: dir)
      uncached = described_class.new(nil, shader_dir: dir, cache_sources: false)

      expect(cached.source("test.wgsl")).to eq("first")
      File.write(path, "second")
      expect(cached.source("test.wgsl")).to eq("first")
      expect(cached.reload!.source("test.wgsl")).to eq("second")
      expect(uncached.source("test.wgsl")).to eq("second")
      File.write(path, "third")
      expect(uncached.source("test.wgsl")).to eq("third")
    end
  end

  it "rejects paths outside the shader directory" do
    Dir.mktmpdir do |dir|
      loader = described_class.new(nil, shader_dir: dir)

      expect { loader.source("../outside.wgsl") }
        .to raise_error(ThreeDgcViewer::ShaderError, /escapes shader directory/)
    end
  end

  it "reports the shader name when module creation fails" do
    device = Class.new do
      def create_shader_module(label:, code:)
        raise "compile failed"
      end
    end.new

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bad.wgsl"), "shader source")
      loader = described_class.new(device, shader_dir: dir)

      expect { loader.module("bad.wgsl") }
        .to raise_error(ThreeDgcViewer::ShaderError, /bad\.wgsl: compile failed/)
    end
  end

  it "caches shader modules and releases them once" do
    device = Class.new do
      attr_reader :modules

      def initialize(module_class)
        @module_class = module_class
        @modules = []
      end

      def create_shader_module(label:, code:)
        @modules << @module_class.new(label)
        @modules.last
      end
    end.new(ShaderModule)

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.wgsl"), "shader source")
      loader = described_class.new(device, shader_dir: dir)

      first = loader.module("test.wgsl")
      second = loader.module("test.wgsl")
      loader.release
      loader.release

      expect(first).to equal(second)
      expect(device.modules.length).to eq(1)
      expect(first.release_count).to eq(1)
    end
  end

  it "releases cached modules when reloading shader sources" do
    device = Class.new do
      attr_reader :modules

      def initialize(module_class)
        @module_class = module_class
        @modules = []
      end

      def create_shader_module(label:, code:)
        @modules << @module_class.new(label)
        @modules.last
      end
    end.new(ShaderModule)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.wgsl")
      File.write(path, "first")
      loader = described_class.new(device, shader_dir: dir)

      first = loader.module("test.wgsl")
      File.write(path, "second")
      loader.reload!
      second = loader.module("test.wgsl")

      expect(first).not_to equal(second)
      expect(first.release_count).to eq(1)
      expect(second.release_count).to eq(0)
      expect(device.modules.length).to eq(2)
    end
  end

  it "rejects use after release" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.wgsl"), "shader source")
      loader = described_class.new(nil, shader_dir: dir)

      loader.release

      expect { loader.source("test.wgsl") }
        .to raise_error(ThreeDgcViewer::ShaderError, /used after release/)
      expect { loader.reload! }
        .to raise_error(ThreeDgcViewer::ShaderError, /used after release/)
    end
  end
end
