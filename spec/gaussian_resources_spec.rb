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

  it "updates render size without reallocating when tile grid is unchanged" do
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(gaussian_set: set, render_width: 320, render_height: 180)
    specs = resources.buffer_specs

    expect(resources.same_tile_grid?(319, 179)).to eq(true)
    expect(resources.resize_render_size!(319, 179)).to equal(resources)
    expect(resources.render_width).to eq(319)
    expect(resources.render_height).to eq(179)
    expect(resources.tiles_width).to eq(20)
    expect(resources.tiles_height).to eq(12)
    expect(resources.buffer_specs).to equal(specs)
    expect(resources.same_tile_grid?(321, 179)).to eq(false)
    expect { resources.resize_render_size!(321, 179) }.to raise_error(ArgumentError, /tile grid/)
  end

  it "allows pair buffer capacity to grow beyond the default" do
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(gaussian_set: set, max_pairs: 4096)

    expect(resources.max_pairs).to eq(4096)
    expect(resources.buffer_specs.find { |spec| spec.name == :pair_keys_buffer }.size).to eq(8 * 4096)
    expect(described_class.next_pair_capacity(4097, 4096)).to eq(8192)
  end

  it "uses configurable default pair capacity factors" do
    item = ThreeDgcViewer::Gaussian::Gaussian3d.new(
      position: [0.0, 0.0, 0.0],
      opacity: 0.0,
      scale: [0.0, 0.0, 0.0],
      rotation: [1.0, 0.0, 0.0, 0.0],
      sh: []
    )
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [item, item])

    resources = described_class.new(gaussian_set: set, pair_capacity_factor: 8)

    expect(resources.max_pairs).to eq(16)
  end

  it "exposes buffer accessors explicitly" do
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(gaussian_set: set)

    expect(resources).to respond_to(:gaussian_buffer)
    expect(resources).to respond_to(:tile_ranges_buffer)
    expect(resources).not_to respond_to(:typo_buffer)
  end

  it "releases created GPU buffers at most once" do
    buffer_class = Class.new do
      attr_reader :release_count

      def initialize
        @release_count = 0
      end

      def release
        @release_count += 1
      end
    end
    device = Class.new do
      attr_reader :buffers

      define_method(:initialize) do
        @buffers = []
      end

      define_method(:create_buffer_with_data) do |label:, data:, usage:|
        create_buffer
      end

      define_method(:create_buffer) do |**_kwargs|
        buffer = buffer_class.new
        @buffers << buffer
        buffer
      end
    end.new
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = described_class.new(device: device, gaussian_set: set)

    resources.release
    resources.release

    expect(device.buffers).not_to be_empty
    expect(device.buffers.map(&:release_count).uniq).to eq([1])
  end
end
