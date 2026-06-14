# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ThreeDgcViewer::CameraBookmarks do
  it "loads named camera presets" do
    file = Tempfile.new(["bookmarks", ".json"])
    file.write(JSON.generate("front" => {"eye" => [1, 2, 3], "target" => [0, 0, 0]}))
    file.close

    bookmark = described_class.fetch_file(file.path, "front")

    expect(bookmark).to include(eye: [1.0, 2.0, 3.0], target: [0.0, 0.0, 0.0])
  ensure
    file&.unlink
  end

  it "writes or replaces a named camera bookmark" do
    file = Tempfile.new(["bookmarks", ".json"])
    path = file.path
    file.close
    file.unlink
    camera = ThreeDgcViewer::Camera.default(width: 640, height: 360)
    camera.eye = [4.0, 5.0, 6.0]

    described_class.write_file(path, " detail ", camera)
    data = JSON.parse(File.read(path))

    expect(data.dig("detail", "eye")).to eq([4.0, 5.0, 6.0])
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it "rejects missing bookmark names" do
    file = Tempfile.new(["bookmarks", ".json"])
    file.write(JSON.generate("front" => {"eye" => [1, 2, 3]}))
    file.close

    expect { described_class.fetch_file(file.path, "side") }
      .to raise_error(ArgumentError, /not found/)
    expect { described_class.write_file(file.path, " ", ThreeDgcViewer::Camera.default(width: 640, height: 360)) }
      .to raise_error(ArgumentError, /must not be empty/)
  ensure
    file&.unlink
  end
end
