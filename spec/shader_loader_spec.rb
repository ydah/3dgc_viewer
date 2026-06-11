# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe ThreeDgcViewer::ShaderLoader do
  it "reads shaders from the configured shader directory" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.wgsl"), "shader source")
      loader = described_class.new(nil, shader_dir: dir)

      expect(loader.source("test.wgsl")).to eq("shader source")
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
end
