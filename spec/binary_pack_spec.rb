# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::BinaryPack do
  it "packs Gaussian3d to 240 bytes" do
    gaussian = ThreeDgcViewer::Gaussian::Gaussian3d.new(
      position: [1.0, 2.0, 3.0],
      opacity: 0.5,
      scale: [0.1, 0.2, 0.3],
      rotation: [1.0, 0.0, 0.0, 0.0],
      sh: Array.new(48, 0.0)
    )

    expect(gaussian.pack.bytesize).to eq(240)
  end

  it "packs Gaussian sets without requiring retained objects when bytes are provided" do
    bytes = "abc".b
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, count: 1, packed_bytes: bytes)

    expect(ThreeDgcViewer::Gaussian.pack_set(set)).to eq(bytes)
  end

  it "packs Gaussian4d to 144 bytes" do
    gaussian = ThreeDgcViewer::Gaussian::Gaussian4d.new(
      position: [1.0, 2.0, 3.0],
      opacity: 0.5,
      scale: [0.1, 0.2, 0.3],
      rotation: [1.0, 0.0, 0.0, 0.0],
      motion_0: [0.0, 0.1, 0.2],
      motion_1: [0.3, 0.4, 0.5],
      motion_2: [0.6, 0.7, 0.8],
      omega: [0.0, 0.0, 0.0, 1.0],
      trbf_center: 0.2,
      trbf_scale: 1.0,
      base_color: [0.1, 0.2, 0.3]
    )

    expect(gaussian.pack.bytesize).to eq(144)
  end

  it "packs SceneUniform to 176 bytes" do
    camera = ThreeDgcViewer::Camera.default(width: 1280, height: 720)
    uniform = ThreeDgcViewer::SceneUniform.new
    uniform.update_camera(camera)
    uniform.update_gaussian_count(0)
    uniform.update_screen_size(321, 181)

    expect(uniform.pack.bytesize).to eq(176)
    expect(uniform.screen_size).to eq([321, 181])
  end

  it "packs fixed GPU helper structures to expected byte sizes" do
    expect(described_class.u32(80, 45, 1024, 0).bytesize).to eq(16)
    expect(described_class.u32(1, 2, 3, 0).bytesize).to eq(16)
    expect(described_class.f32(1, 2, 3, 1, 0, 0).bytesize).to eq(24)
    expect(ThreeDgcViewer::Passes::AxisPass.vertex_bytes.bytesize).to eq(24 * 6)
  end
end
