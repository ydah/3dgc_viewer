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
      "--background-color", "#112233",
      "--transparent-background",
      "--exposure", "1.5",
      "--gamma", "2.2",
      "--brightness", "0.1",
      "--contrast", "1.2",
      "--opacity-threshold", "0.01",
      "--scale-multiplier", "0.75",
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
      background_color: "#112233",
      transparent_background: true,
      exposure: 1.5,
      gamma: 2.2,
      brightness: 0.1,
      contrast: 1.2,
      opacity_threshold: 0.01,
      scale_multiplier: 0.75,
      camera_preset: "camera.json",
      assert_nonzero: true
    )

    expect(result).to eq(0)
  end
end
