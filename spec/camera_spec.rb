# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Camera do
  it "fits a bounding sphere into the camera frustum" do
    camera = described_class.default(width: 1280, height: 720)
    bounds = ThreeDgcViewer::Gaussian::Bounds.new(
      min: [-2.0, -1.0, -3.0],
      max: [2.0, 3.0, 1.0]
    )

    camera.fit_bounds(bounds)

    expect(camera.target).to eq([0.0, 1.0, -1.0])
    expect(camera.znear).to be > 0.0
    expect(camera.zfar).to be > camera.znear
    distance = ThreeDgcViewer::Math3D::Vec3.length(
      ThreeDgcViewer::Math3D::Vec3.sub(camera.eye, camera.target)
    )
    expect(distance).to be > bounds.radius
  end
end

RSpec.describe ThreeDgcViewer::CameraController do
  it "scales zoom speed from scene radius" do
    camera = ThreeDgcViewer::Camera.default(width: 1280, height: 720)
    controller = described_class.new
    controller.sync_from_camera(camera)
    initial_radius = controller.radius

    controller.fit_scene_radius(100.0)
    controller.handle_key(ThreeDgcViewer::Window::Keymap::KEY_Q, true)
    controller.update_camera(camera, 1.0)

    expect(controller.radius).to be < initial_radius
  end
end
