# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ThreeDgcViewer::App do
  def required_3d
    %w[
      x y z opacity scale_0 scale_1 scale_2
      rot_0 rot_1 rot_2 rot_3 f_dc_0 f_dc_1 f_dc_2
    ]
  end

  def build_ply_file
    file = Tempfile.new(["scene", ".ply"])
    header = +"ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
    required_3d.each { |name| header << "property float #{name}\n" }
    header << "end_header\n"
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    file.binmode
    file.write(header.b)
    file.write(row.pack("e*"))
    file.close
    file
  end

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

  it "derives render size from render scale" do
    options = described_class.parse_options(%w[
      --width 640
      --height 360
      --render-scale 0.5
    ])

    expect(options.render_width).to eq(320)
    expect(options.render_height).to eq(180)
  end

  it "rejects invalid log level" do
    expect { described_class.parse_options(%w[--log-level trace]) }
      .to raise_error(OptionParser::InvalidArgument, /log-level/)
  end

  it "rejects invalid dimensions" do
    expect { described_class.parse_options(%w[--width 0]) }
      .to raise_error(OptionParser::InvalidArgument, /width/)
  end

  it "checks startup file paths during option parsing" do
    expect { described_class.parse_options(%w[--file /missing/model.ply]) }
      .to raise_error(OptionParser::InvalidArgument, /does not exist/)
  end

  it "prints scene information without initializing the window" do
    file = build_ply_file
    result = nil

    expect do
      result = described_class.run(["--file", file.path, "--print-scene-info"])
    end.to output(/kind: gaussian3d\n/).to_stdout

    expect(result).to eq(0)
  ensure
    file&.unlink
  end
end
