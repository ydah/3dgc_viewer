# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::GaussianResources do
  it "derives resource sizes for an empty 3D scene" do
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(gaussian_set: set)

    expect(resources.gaussian_count).to eq(0)
    expect(resources.count1).to eq(1)
    expect(resources.max_pairs).to eq(32)
    expect(resources.tiles_width).to eq(80)
    expect(resources.tiles_height).to eq(45)
    expect(resources.tile_count).to eq(3600)
    expect(resources.buffer_specs.find { |spec| spec.name == :gaussian_buffer }.size).to eq(240)
    expect(resources.estimated_buffer_bytes).to eq(resources.buffer_specs.sum(&:size))
  end

  it "derives resource sizes for a 4D scene" do
    item = ThreeDgcViewer::Gaussian::Gaussian4d.new(
      position: [0.0, 0.0, 0.0],
      opacity: 0.0,
      scale: [0.0, 0.0, 0.0],
      rotation: [1.0, 0.0, 0.0, 0.0],
      motion_0: [0.0, 0.0, 0.0],
      motion_1: [0.0, 0.0, 0.0],
      motion_2: [0.0, 0.0, 0.0],
      omega: [0.0, 0.0, 0.0, 0.0],
      trbf_center: 0.0,
      trbf_scale: 0.0,
      base_color: [0.0, 0.0, 0.0]
    )
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian4d, items: [item, item])

    resources = described_class.new(gaussian_set: set)

    expect(resources.gaussian_count).to eq(2)
    expect(resources.max_pairs).to eq(64)
    expect(resources.buffer_specs.find { |spec| spec.name == :gaussian_buffer }.size).to eq(288)
  end

  it "derives tile resources from a custom render size" do
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(gaussian_set: set, render_width: 321, render_height: 181)

    expect(resources.render_width).to eq(321)
    expect(resources.render_height).to eq(181)
    expect(resources.tiles_width).to eq(21)
    expect(resources.tiles_height).to eq(12)
    expect(resources.tile_count).to eq(252)
    expect(resources.buffer_specs.find { |spec| spec.name == :tile_ranges_buffer }.size).to eq(8 * 252)
  end

  it "allows pair buffer capacity to grow beyond the default" do
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(gaussian_set: set, max_pairs: 4096)

    expect(resources.max_pairs).to eq(4096)
    expect(resources.buffer_specs.find { |spec| spec.name == :pair_keys_buffer }.size).to eq(8 * 4096)
    expect(described_class.next_pair_capacity(4097, 4096)).to eq(8192)
  end
end
