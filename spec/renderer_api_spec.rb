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
      assert_nonzero: true
    )

    expect(result).to eq(0)
  end
end
