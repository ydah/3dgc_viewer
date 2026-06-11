# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ThreeDgcViewer.render" do
  it "delegates to screenshot batch mode" do
    expect(ThreeDgcViewer::App).to receive(:run).with([
      "--file", "scene.ply",
      "--screenshot", "frame.ppm",
      "--hidden",
      "--width", "640",
      "--height", "360",
      "--render-width", "320",
      "--render-height", "180",
      "--render-scale", "0.5",
      "--background-color", "#112233",
      "--transparent-background",
      "--exposure", "1.5",
      "--gamma", "2.2",
      "--brightness", "0.1",
      "--contrast", "1.2",
      "--opacity-threshold", "0.01",
      "--scale-multiplier", "0.75",
      "--sh-degree", "1",
      "--max-gaussians", "123",
      "--max-file-bytes", "456",
      "--time", "0.25",
      "--time-speed", "2.0",
      "--time-range", "0.1,0.9",
      "--pause",
      "--quality", "fast",
      "--low-vram",
      "--camera-preset", "camera.json",
      "--assert-render-nonzero"
    ]).and_return(0)

    result = ThreeDgcViewer.render(
      "scene.ply",
      output: "frame.ppm",
      width: 640,
      height: 360,
      render_width: 320,
      render_height: 180,
      render_scale: 0.5,
      background_color: "#112233",
      transparent_background: true,
      exposure: 1.5,
      gamma: 2.2,
      brightness: 0.1,
      contrast: 1.2,
      opacity_threshold: 0.01,
      scale_multiplier: 0.75,
      sh_degree: 1,
      max_gaussians: 123,
      max_file_bytes: 456,
      time: 0.25,
      time_speed: 2.0,
      time_range: [0.1, 0.9],
      pause: true,
      quality: :fast,
      low_vram: true,
      camera_preset: "camera.json",
      assert_nonzero: true
    )

    expect(result).to eq(0)
  end
end
