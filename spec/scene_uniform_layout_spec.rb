# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SceneUniform WGSL layout" do
  FULL_SCENE_UNIFORM_TYPES = %w[
    mat4x4<f32>
    mat4x4<f32>
    vec3<f32>
    u32
    vec2<u32>
    vec2<f32>
    vec2<f32>
    f32
    u32
    vec4<f32>
    vec2<f32>
    vec2<u32>
    vec4<f32>
  ].freeze

  AXIS_SCENE_UNIFORM_TYPES = FULL_SCENE_UNIFORM_TYPES.first(9).freeze

  def shader_path(name)
    File.expand_path("../shaders/#{name}", __dir__)
  end

  def scene_uniform_types(name)
    source = File.read(shader_path(name))
    body = source.match(/struct\s+SceneUniform\s*\{(?<body>.*?)\}/m)&.[](:body)
    raise "SceneUniform not found in #{name}" unless body

    body.scan(/^\s*[A-Za-z_][A-Za-z0-9_]*\s*:\s*([^,\n}]+)/).flatten.map(&:strip)
  end

  it "keeps Ruby SceneUniform byte size aligned with the full WGSL layout" do
    expect(ThreeDgcViewer::SceneUniform.new.pack.bytesize).to eq(224)
    expect(FULL_SCENE_UNIFORM_TYPES).to eq([
      "mat4x4<f32>", "mat4x4<f32>", "vec3<f32>", "u32",
      "vec2<u32>", "vec2<f32>", "vec2<f32>", "f32", "u32",
      "vec4<f32>", "vec2<f32>", "vec2<u32>", "vec4<f32>"
    ])
  end

  it "keeps full SceneUniform shader declarations in sync" do
    %w[
      preprocess_3d.compute.wgsl
      preprocess_4d.compute.wgsl
      tile_render.compute.wgsl
    ].each do |name|
      expect(scene_uniform_types(name)).to eq(FULL_SCENE_UNIFORM_TYPES), name
    end
  end

  it "keeps the axis shader SceneUniform declaration as a prefix layout" do
    expect(scene_uniform_types("axis.wgsl")).to eq(AXIS_SCENE_UNIFORM_TYPES)
  end
end
