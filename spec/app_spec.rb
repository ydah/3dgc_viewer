# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::App do
  it "parses internal render size options" do
    options = described_class.parse_options(%w[
      --render-width 321
      --render-height 181
      --render-size-window
    ])

    expect(options.render_width).to eq(321)
    expect(options.render_height).to eq(181)
    expect(options.render_size_window).to eq(true)
  end
end
