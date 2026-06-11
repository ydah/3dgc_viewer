# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Window::GLFW do
  it "describes Linux display setup in platform hints" do
    allow(ThreeDgcViewer::LibraryLocator).to receive(:platform).and_return("linux-x64")

    expect(described_class.platform_hint).to include("DISPLAY")
  end

  it "describes GLFW_LIB setup in platform hints" do
    allow(ThreeDgcViewer::LibraryLocator).to receive(:platform).and_return("windows-x64")

    expect(described_class.platform_hint).to include("GLFW_LIB")
  end
end
