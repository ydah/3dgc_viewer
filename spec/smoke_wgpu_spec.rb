# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tempfile"

RSpec.describe "wgpu smoke" do
  it "creates a wgpu instance and loads the surface shim when explicitly requested" do
    skip "set RUN_WGPU_SMOKE=1 to run GPU smoke tests" unless ENV["RUN_WGPU_SMOKE"] == "1"

    require "wgpu"

    expect(File.file?(WGPU::Native.library_path)).to eq(true)
    expect { ThreeDgcViewer::WGPU::SurfaceShim.load! }.not_to raise_error
    instance = WGPU::Instance.new
    expect(instance.handle.null?).to eq(false)
  end

  it "renders a 3DGS smoke frame with non-black RGB output" do
    skip "set RUN_WGPU_FRAME_SMOKE=1 to run frame smoke tests" unless ENV["RUN_WGPU_FRAME_SMOKE"] == "1"

    with_smoke_ply(kind: :gaussian3d) do |path|
      expect_smoke_frame(path, render_size_window: false)
    end
  end

  it "renders a STG-Lite smoke frame with non-black RGB output" do
    skip "set RUN_WGPU_FRAME_SMOKE=1 to run frame smoke tests" unless ENV["RUN_WGPU_FRAME_SMOKE"] == "1"

    with_smoke_ply(kind: :gaussian4d) do |path|
      expect_smoke_frame(path, render_size_window: true)
    end
  end

  def expect_smoke_frame(path, render_size_window:)
    command = [
      RbConfig.ruby,
      File.expand_path("../bin/3dgc_viewer", __dir__),
      "--hidden",
      "--smoke-frame",
      "--smoke-resize",
      "--smoke-camera",
      "--assert-render-nonzero",
      "--width",
      "320",
      "--height",
      "180",
      "--render-width",
      "321",
      "--render-height",
      "181"
    ]
    command << "--render-size-window" if render_size_window
    command.concat(["--file", path])
    stdout, stderr, status = Open3.capture3({"RUBYLIB" => File.expand_path("../lib", __dir__)}, *command)
    expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
  end

  def with_smoke_ply(kind:)
    Tempfile.create(["3dgc_viewer_smoke", ".ply"]) do |file|
      fields, values = smoke_payload(kind)
      header = +"ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
      fields.each { |field| header << "property float #{field}\n" }
      header << "end_header\n"
      file.binmode
      file.write(header.b)
      file.write(values.pack("e*"))
      file.flush
      yield file.path
    end
  end

  def smoke_payload(kind)
    core = %w[
      x y z opacity scale_0 scale_1 scale_2
      rot_0 rot_1 rot_2 rot_3 f_dc_0 f_dc_1 f_dc_2
    ]
    values = [0.0, 0.0, 0.0, 0.9, -2.0, -2.0, -2.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.2, 0.1]
    return [core, values] if kind == :gaussian3d

    stg = %w[
      trbf_center trbf_scale
      motion_0 motion_1 motion_2 motion_3 motion_4 motion_5 motion_6 motion_7 motion_8
      omega_0 omega_1 omega_2 omega_3
    ]
    stg_values = Array.new(stg.length, 0.0)
    stg_values[0] = 0.5
    stg_values[1] = 1.0
    stg_values[11] = 1.0
    [core + stg, values + stg_values]
  end
end
