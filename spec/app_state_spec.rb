# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"
require "tempfile"

RSpec.describe ThreeDgcViewer::AppState do
  FakeWindow = Struct.new(:width, :height, :title) do
    def framebuffer_size
      [width, height]
    end
  end

  def build_ply_file
    file = Tempfile.new(["scene", ".ply"])
    required = %w[
      x y z opacity scale_0 scale_1 scale_2
      rot_0 rot_1 rot_2 rot_3 f_dc_0 f_dc_1 f_dc_2
    ]
    header = +"ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
    required.each { |name| header << "property float #{name}\n" }
    header << "end_header\n"
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    file.binmode
    file.write(header.b)
    file.write(row.pack("e*"))
    file.close
    file
  end

  def quiet_logger
    Logger.new(StringIO.new)
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

  it "handles fit reset and axis toggle shortcuts" do
    state = described_class.new(FakeWindow.new(1280, 720))
    bounds = ThreeDgcViewer::Gaussian::Bounds.new(
      min: [10.0, 20.0, 30.0],
      max: [12.0, 22.0, 32.0]
    )
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(
      kind: :gaussian3d,
      count: 0,
      statistics: ThreeDgcViewer::Gaussian::Statistics.new(count: 0, bounds: bounds, invalid_count: 0)
    )
    state.replace_gaussians(set)

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_R, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.camera.target).to eq([0.0, 0.0, 0.0])

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_F, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.camera.target).to eq([11.0, 21.0, 31.0])

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_X, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.show_axis).to eq(false)
  end

  it "updates the window title after loading a file" do
    file = build_ply_file
    window = FakeWindow.new(1280, 720)
    state = described_class.new(window, logger: quiet_logger)

    state.handle_drop(file.path)

    expect(window.title).to include(File.basename(file.path))
    expect(window.title).to include("1 gaussians")
  ensure
    file&.unlink
  end
end
