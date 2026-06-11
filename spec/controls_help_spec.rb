# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::ControlsHelp do
  it "exposes controls as structured entries and text" do
    expect(described_class.entries).to include(keys: "F", action: "Fit view to scene")
    expect(described_class.entries).to include(keys: "Space", action: "Toggle playback pause")
    expect(described_class.entries).to include(keys: "T", action: "Toggle turntable animation")
    expect(described_class.text).to include("Left mouse drag: Orbit camera")
  end
end
