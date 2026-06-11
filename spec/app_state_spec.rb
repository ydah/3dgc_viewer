# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::AppState do
  FakeWindow = Struct.new(:width, :height) do
    def framebuffer_size
      [width, height]
    end
  end

  it "fits the camera when replacing gaussians with scene bounds" do
    state = described_class.new(FakeWindow.new(1280, 720))
    bounds = ThreeDgcViewer::Gaussian::Bounds.new(
      min: [10.0, 20.0, 30.0],
      max: [12.0, 22.0, 32.0]
    )
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(
      kind: :gaussian3d,
      count: 0,
      statistics: ThreeDgcViewer::Gaussian::Statistics.new(
        count: 0,
        bounds: bounds,
        invalid_count: 0
      )
    )

    state.replace_gaussians(set)

    expect(state.camera.target).to eq([11.0, 21.0, 31.0])
    expect(state.camera.zfar).to be > state.camera.znear
  end
end
