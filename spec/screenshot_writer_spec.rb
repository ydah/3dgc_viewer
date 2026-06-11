# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ThreeDgcViewer::ScreenshotWriter do
  it "encodes RGBA bytes as binary PPM RGB bytes" do
    rgba = [
      255, 0, 0, 255,
      0, 128, 0, 255
    ].pack("C*")

    ppm = described_class.ppm_bytes(width: 2, height: 1, rgba_bytes: rgba)

    expect(ppm).to eq("P6\n2 1\n255\n".b + [255, 0, 0, 0, 128, 0].pack("C*"))
  end

  it "rejects mismatched RGBA byte sizes" do
    expect { described_class.ppm_bytes(width: 2, height: 1, rgba_bytes: "\0\0\0\0".b) }
      .to raise_error(ArgumentError, /rgba bytes size/)
  end

  it "encodes RGBA bytes as PAM with alpha" do
    rgba = [1, 2, 3, 4].pack("C*")

    pam = described_class.pam_bytes(width: 1, height: 1, rgba_bytes: rgba)

    expect(pam).to eq("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n".b + rgba)
  end

  it "writes PPM files" do
    file = Tempfile.new(["screenshot", ".ppm"])
    rgba = [1, 2, 3, 255].pack("C*")

    described_class.write_ppm(path: file.path, width: 1, height: 1, rgba_bytes: rgba)

    expect(File.binread(file.path)).to eq("P6\n1 1\n255\n".b + [1, 2, 3].pack("C*"))
    expect(File).not_to exist("#{file.path}.tmp")
  ensure
    file&.unlink
  end

  it "writes PAM files based on extension" do
    file = Tempfile.new(["screenshot", ".pam"])
    rgba = [1, 2, 3, 4].pack("C*")

    described_class.write(path: file.path, width: 1, height: 1, rgba_bytes: rgba)

    expect(File.binread(file.path)).to end_with(rgba)
  ensure
    file&.unlink
  end
end
