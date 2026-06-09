# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Math3D do
  it "builds a basic right-handed look-at matrix" do
    matrix = described_class::Mat4.look_at_rh([0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0])

    expect(matrix[0]).to be_within(1e-6).of(1.0)
    expect(matrix[5]).to be_within(1e-6).of(1.0)
    expect(matrix[10]).to be_within(1e-6).of(1.0)
    expect(matrix[14]).to be_within(1e-6).of(-1.0)
  end

  it "builds a perspective matrix with expected focal values" do
    matrix = described_class::Mat4.perspective_rh(Math::PI / 2.0, 2.0, 0.1, 100.0)

    expect(matrix[0]).to be_within(1e-6).of(0.5)
    expect(matrix[5]).to be_within(1e-6).of(1.0)
  end

  it "rotates a Vec3 with a quaternion" do
    quat = described_class::Quat.from_axis_angle([0.0, 0.0, 1.0], Math::PI / 2.0)
    vec = described_class::Quat.rotate_vec3(quat, [1.0, 0.0, 0.0])

    expect(vec[0]).to be_within(1e-6).of(0.0)
    expect(vec[1]).to be_within(1e-6).of(1.0)
    expect(vec[2]).to be_within(1e-6).of(0.0)
  end
end
