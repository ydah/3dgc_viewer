# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GPU struct layouts" do
  GAUSSIAN_3D_TYPES = [
    "vec3<f32>", "f32",
    "vec3<f32>", "u32",
    "vec4<f32>",
    "array<f32, 48>"
  ].freeze

  GAUSSIAN_4D_TYPES = [
    "vec3<f32>", "f32",
    "vec3<f32>", "u32",
    "vec4<f32>",
    "vec3<f32>", "u32",
    "vec3<f32>", "u32",
    "vec3<f32>", "u32",
    "vec4<f32>",
    "f32", "f32", "u32", "u32",
    "vec3<f32>", "u32"
  ].freeze

  PREPROCESS_OUTPUT_TYPES = [
    "vec4<f32>",
    "vec4<f32>",
    "vec4<u32>",
    "vec4<f32>"
  ].freeze

  TILE_RANGE_TYPES = %w[u32 u32].freeze
  TOTAL_PAIRS_TYPES = %w[u32 u32 u32 u32].freeze

  def shader_path(name)
    File.expand_path("../shaders/#{name}", __dir__)
  end

  def struct_types(shader, struct_name)
    source = File.read(shader_path(shader))
    body = source.match(/struct\s+#{Regexp.escape(struct_name)}\s*\{(?<body>.*?)\}/m)&.[](:body)
    raise "#{struct_name} not found in #{shader}" unless body

    body.lines.filter_map do |line|
      type = line[/^\s*[A-Za-z_][A-Za-z0-9_]*\s*:\s*(.*?)(?:\s*\/\/.*)?$/, 1]
      next unless type

      type.strip.delete_suffix(",")
    end
  end

  it "keeps Gaussian3d Ruby packing aligned with WGSL" do
    expect(ThreeDgcViewer::Gaussian.item_size(:gaussian3d)).to eq(240)
    expect(struct_types("preprocess_3d.compute.wgsl", "Gaussian3d")).to eq(GAUSSIAN_3D_TYPES)
  end

  it "keeps Gaussian4d Ruby packing aligned with WGSL" do
    expect(ThreeDgcViewer::Gaussian.item_size(:gaussian4d)).to eq(144)
    expect(struct_types("preprocess_4d.compute.wgsl", "Gaussian4d")).to eq(GAUSSIAN_4D_TYPES)
  end

  it "keeps PreprocessOutput declarations in sync across compute shaders" do
    %w[
      preprocess_3d.compute.wgsl
      preprocess_4d.compute.wgsl
      duplicate.compute.wgsl
      tile_render.compute.wgsl
    ].each do |shader|
      expect(struct_types(shader, "PreprocessOutput")).to eq(PREPROCESS_OUTPUT_TYPES), shader
    end
  end

  it "keeps tile range and total pair layouts stable" do
    expect(struct_types("tile_render.compute.wgsl", "TileRange")).to eq(TILE_RANGE_TYPES)
    expect(struct_types("tile_render.compute.wgsl", "TotalPairs")).to eq(TOTAL_PAIRS_TYPES)
  end
end
