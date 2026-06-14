# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ThreeDgcViewer::CameraPreset do
  it "loads camera preset fields from JSON" do
    preset = described_class.load_hash(
      "eye" => [1, 2, 3],
      "target" => [4, 5, 6],
      "up" => [0, 1, 0],
      "fov" => 60,
      "znear" => 0.2,
      "zfar" => 200
    )

    expect(preset).to include(
      eye: [1.0, 2.0, 3.0],
      target: [4.0, 5.0, 6.0],
      up: [0.0, 1.0, 0.0],
      fov: 60.0,
      znear: 0.2,
      zfar: 200.0
    )
  end

  it "rejects invalid vector fields" do
    expect { described_class.load_hash("eye" => [1, 2]) }
      .to raise_error(ArgumentError, /eye/)
  end

  it "writes camera presets as JSON" do
    file = Tempfile.new(["camera", ".json"])
    path = file.path
    file.close
    file.unlink
    camera = ThreeDgcViewer::Camera.default(width: 640, height: 360)
    camera.eye = [1.0, 2.0, 3.0]

    described_class.write_file(path, camera)
    data = JSON.parse(File.read(path))

    expect(data.fetch("eye")).to eq([1.0, 2.0, 3.0])
    expect(data.fetch("fov")).to eq(45.0)
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
