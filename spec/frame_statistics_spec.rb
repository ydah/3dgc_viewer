# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::FrameStatistics do
  it "records average and percentile frame times in milliseconds" do
    stats = described_class.new

    [0.001, 0.002, 0.003, 0.004].each { |seconds| stats.record(seconds) }

    expect(stats.snapshot).to include(
      count: 4,
      average_ms: 2.5,
      p50_ms: 2.0,
      p95_ms: 4.0,
      p99_ms: 4.0
    )
  end

  it "keeps only the most recent samples" do
    stats = described_class.new(max_samples: 2)

    [0.001, 0.002, 0.003].each { |seconds| stats.record(seconds) }

    expect(stats.snapshot).to include(
      count: 2,
      p50_ms: 2.0,
      p95_ms: 3.0
    )
  end

  it "ignores invalid samples and can reset" do
    stats = described_class.new

    expect(stats.record(Float::NAN)).to eq(false)
    expect(stats.snapshot).to be_nil

    stats.record(0.001)
    stats.reset

    expect(stats.snapshot).to be_nil
  end
end
