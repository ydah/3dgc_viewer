# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Passes::TileRangePass do
  it "can clear tile ranges without dispatching the range build" do
    gaussian_set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, items: [])
    resources = ThreeDgcViewer::GaussianResources.new(
      gaussian_set: gaussian_set,
      render_width: 32,
      render_height: 32
    )
    encoder = Class.new do
      attr_reader :dispatches, :indirect_dispatches

      def initialize
        @dispatches = []
        @indirect_dispatches = []
      end

      def dispatch_compute(name, x, y, z)
        @dispatches << [name, x, y, z]
      end

      def dispatch_compute_indirect(name, buffer, offset)
        @indirect_dispatches << [name, buffer, offset]
      end
    end.new
    pass = described_class.new(resources: resources, shader_loader: nil)

    pass.encode(encoder, clear_only: true)

    expect(encoder.dispatches).to eq([["clear_tile_ranges.compute.wgsl", 1, 1, 1]])
    expect(encoder.indirect_dispatches).to be_empty
  end
end
