# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::ByteSize do
  it "formats byte counts using binary units" do
    expect(described_class.format(512)).to eq("512.0 B")
    expect(described_class.format(1536)).to eq("1.5 KiB")
    expect(described_class.format(5 * 1024 * 1024)).to eq("5.0 MiB")
  end
end
