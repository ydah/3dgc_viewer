# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"
require "tmpdir"

RSpec.describe ThreeDgcViewer::LibraryLocator do
  it "reports environment provenance and existence" do
    file = Tempfile.new("libwgpu_native")
    previous = ENV["WGPU_NATIVE_LIB"]
    ENV["WGPU_NATIVE_LIB"] = file.path

    location = described_class.wgpu_native_location

    expect(location.path).to eq(file.path)
    expect(location.source).to eq(:env)
    expect(location.exists).to eq(true)
  ensure
    ENV["WGPU_NATIVE_LIB"] = previous
    file&.close
    file&.unlink
  end

  it "prefers common Windows GLFW dll names in vendored libraries" do
    previous = ENV["GLFW_LIB"]
    ENV.delete("GLFW_LIB")

    Dir.mktmpdir do |dir|
      vendor_dir = File.join(dir, "vendor", "glfw", "windows-x64")
      FileUtils.mkdir_p(vendor_dir)
      path = File.join(vendor_dir, "glfw3.dll")
      File.binwrite(path, "")
      allow(described_class).to receive(:root).and_return(dir)
      allow(described_class).to receive(:platform).and_return("windows-x64")

      location = described_class.glfw_location

      expect(location.path).to eq(path)
      expect(location.source).to eq(:vendor)
      expect(location.exists).to eq(true)
    end
  ensure
    ENV["GLFW_LIB"] = previous
  end

  it "uses glfw3.dll as the Windows GLFW fallback name" do
    previous = ENV["GLFW_LIB"]
    ENV.delete("GLFW_LIB")
    allow(described_class).to receive(:platform).and_return("windows-x64")
    allow(described_class).to receive(:root).and_return("/missing")

    location = described_class.glfw_location

    expect(location.path).to eq("glfw3.dll")
    expect(location.source).to eq(:fallback)
  ensure
    ENV["GLFW_LIB"] = previous
  end
end
