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

  it "packs Gaussian3d directly without changing the byte layout" do
    gaussian = ThreeDgcViewer::Gaussian::Gaussian3d.new(
      position: [1.0, 2.0, 3.0],
      opacity: 0.5,
      scale: [0.1, 0.2, 0.3],
      rotation: [1.0, 0.0, 0.0, 0.0],
      sh: Array.new(48, 0.25)
    )

    direct = ThreeDgcViewer::Gaussian.pack_3d(
      position: gaussian.position,
      opacity: gaussian.opacity,
      scale: gaussian.scale,
      rotation: gaussian.rotation,
      sh: gaussian.sh
    )

    expect(direct).to eq(gaussian.pack)
  end

  it "packs Gaussian sets without requiring retained objects when bytes are provided" do
    bytes = "abc".b
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(kind: :gaussian3d, count: 1, packed_bytes: bytes)

    expect(ThreeDgcViewer::Gaussian.pack_set(set)).to eq(bytes)
  end

  it "creates binary buffers for packed Gaussian output" do
    buffer = ThreeDgcViewer::Gaussian.packed_buffer(:gaussian3d, 1)
    buffer << "abc".b

    expect(buffer.encoding).to eq(Encoding::BINARY)
    expect(buffer).to eq("abc".b)
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

  it "packs Gaussian4d directly without changing the byte layout" do
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

    direct = ThreeDgcViewer::Gaussian.pack_4d(
      position: gaussian.position,
      opacity: gaussian.opacity,
      scale: gaussian.scale,
      rotation: gaussian.rotation,
      motion_0: gaussian.motion_0,
      motion_1: gaussian.motion_1,
      motion_2: gaussian.motion_2,
      omega: gaussian.omega,
      trbf_center: gaussian.trbf_center,
      trbf_scale: gaussian.trbf_scale,
      base_color: gaussian.base_color
    )

    expect(direct).to eq(gaussian.pack)
  end

  it "packs SceneUniform to 224 bytes" do
    camera = ThreeDgcViewer::Camera.default(width: 1280, height: 720)
    uniform = ThreeDgcViewer::SceneUniform.new(
      background_color: [0.1, 0.2, 0.3, 1.0],
      exposure: 1.5,
      gamma: 2.2,
      brightness: 0.1,
      contrast: 1.2,
      opacity_threshold: 0.01,
      scale_multiplier: 0.75
    )
    uniform.update_camera(camera)
    uniform.update_gaussian_count(0)
    uniform.update_screen_size(321, 181)

    expect(uniform.pack.bytesize).to eq(224)
    expect(uniform.screen_size).to eq([321, 181])
    expect(uniform.background_color).to eq([0.1, 0.2, 0.3, 1.0])
    expect(uniform.exposure).to eq(1.5)
    expect(uniform.gamma).to eq(2.2)
    expect(uniform.brightness).to eq(0.1)
    expect(uniform.contrast).to eq(1.2)
    expect(uniform.opacity_threshold).to eq(0.01)
    expect(uniform.scale_multiplier).to eq(0.75)
  end

  it "updates SceneUniform time with runtime playback speed" do
    uniform = ThreeDgcViewer::SceneUniform.new

    uniform.set_time(0.25)
    uniform.update_time(0.5, speed: 2.0)

    expect(uniform.time).to eq(0.25)
  end

  it "packs fixed GPU helper structures to expected byte sizes" do
    expect(described_class.u32(80, 45, 1024, 0).bytesize).to eq(16)
    expect(described_class.u32(1, 2, 3, 0).bytesize).to eq(16)
    expect(described_class.f32(1, 2, 3, 1, 0, 0).bytesize).to eq(24)
    expect(ThreeDgcViewer::Passes::AxisPass.vertex_bytes.bytesize).to eq(24 * 6)
  end

  it "packs flat arrays and nested arrays with the same public API" do
    expect(described_class.u32([1, 2, 3])).to eq([1, 2, 3].pack("L<*").b)
    expect(described_class.f32([[1.0, 2.0], [3.0]])).to eq([1.0, 2.0, 3.0].pack("e*").b)
  end

  it "concatenates chunks into a binary string" do
    result = described_class.concat("ab".b, "cd".b)

    expect(result).to eq("abcd".b)
    expect(result.encoding).to eq(Encoding::BINARY)
  end
end
