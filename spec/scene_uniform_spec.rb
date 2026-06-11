# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::SceneUniform do
  it "wraps time over the default unit interval" do
    uniform = described_class.new

    uniform.set_time(1.25)

    expect(uniform.time).to eq(0.25)
  end

  it "wraps time inside a configured playback range" do
    uniform = described_class.new
    uniform.set_time(0.55, range: [0.2, 0.6])

    uniform.update_time(0.2, speed: 1.0, range: [0.2, 0.6])

    expect(uniform.time).to be_within(1e-9).of(0.35)
  end
end
