# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Window::GLFW do
  after do
    described_class.instance_variable_set(:@glfw_ref_count, 0)
  end

  it "describes Linux display setup in platform hints" do
    allow(ThreeDgcViewer::LibraryLocator).to receive(:platform).and_return("linux-x64")

    expect(described_class.platform_hint).to include("DISPLAY")
  end

  it "describes GLFW_LIB setup in platform hints" do
    allow(ThreeDgcViewer::LibraryLocator).to receive(:platform).and_return("windows-x64")

    expect(described_class.platform_hint).to include("GLFW_LIB")
  end

  it "terminates GLFW only after the last window is destroyed" do
    first_ptr = FFI::MemoryPointer.new(:char)
    second_ptr = FFI::MemoryPointer.new(:char)
    native = described_class::Native
    allow(native).to receive(:load!)
    expect(native).to receive(:glfwInit).once.and_return(1)
    expect(native).to receive(:glfwTerminate).once
    allow(native).to receive(:glfwWindowHint)
    allow(native).to receive(:glfwCreateWindow).and_return(first_ptr, second_ptr)
    allow(native).to receive(:glfwDestroyWindow)
    allow(native).to receive(:glfwSetKeyCallback)
    allow(native).to receive(:glfwSetDropCallback)
    allow(native).to receive(:glfwSetFramebufferSizeCallback)
    allow(native).to receive(:glfwSetCursorPosCallback)
    allow(native).to receive(:glfwSetMouseButtonCallback)
    allow(native).to receive(:glfwSetScrollCallback)

    first = described_class.new(width: 100, height: 100, title: "first")
    second = described_class.new(width: 100, height: 100, title: "second")

    first.destroy
    expect(described_class.glfw_ref_count).to eq(1)

    second.destroy
    expect(described_class.glfw_ref_count).to eq(0)
  end
end
