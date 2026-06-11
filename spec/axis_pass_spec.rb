# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Passes::AxisPass do
  it "packs vertices using the requested axis length" do
    floats = described_class.vertex_bytes(2.5).unpack("e*")

    expect(floats[0, 4]).to eq([-2.5, 0.0, 0.0, 1.0])
    expect(floats[4]).to be_within(1e-6).of(0.1)
    expect(floats[5]).to be_within(1e-6).of(0.1)
    expect(floats[6, 4]).to eq([2.5, 0.0, 0.0, 1.0])
    expect(floats[10]).to be_within(1e-6).of(0.1)
    expect(floats[11]).to be_within(1e-6).of(0.1)
  end

  it "keeps a minimum visible axis length" do
    floats = described_class.vertex_bytes(0.0).unpack("e*")

    expect(floats.first).to eq(-1.0)
  end
end
