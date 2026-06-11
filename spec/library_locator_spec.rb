# frozen_string_literal: true

require "spec_helper"
require "tempfile"

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
end
