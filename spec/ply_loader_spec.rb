# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "zlib"

RSpec.describe ThreeDgcViewer::PlyLoader do
  REQUIRED_3D = %w[
    x y z opacity scale_0 scale_1 scale_2
    rot_0 rot_1 rot_2 rot_3 f_dc_0 f_dc_1 f_dc_2
  ].freeze

  REQUIRED_STG = %w[
    trbf_center trbf_scale
    motion_0 motion_1 motion_2 motion_3 motion_4 motion_5 motion_6 motion_7 motion_8
    omega_0 omega_1 omega_2 omega_3
  ].freeze

  def build_ply(properties, rows, format: "binary_little_endian", header_lines: [])
    header = +"ply\nformat #{format} 1.0\nelement vertex #{rows.length}\n"
    header_lines.each { |line| header << "#{line}\n" }
    properties.each { |type, name| header << "property #{type} #{name}\n" }
    header << "end_header\n"

    body =
      if format == "ascii"
        rows.map { |row| row.join(" ") }.join("\n") + "\n"
      else
        big_endian = format == "binary_big_endian"
        rows.map do |row|
          properties.each_with_index.map { |(type, _name), index| pack_scalar(type, row[index], big_endian: big_endian) }.join
        end.join
      end

    (header + body).b
  end

  def pack_scalar(type, value, big_endian: false)
    case type
    when "char", "int8" then [value].pack("c")
    when "uchar", "uint8" then [value].pack("C")
    when "short", "int16" then [value].pack(big_endian ? "s>" : "s<")
    when "ushort", "uint16" then [value].pack(big_endian ? "S>" : "S<")
    when "int", "int32" then [value].pack(big_endian ? "l>" : "l<")
    when "uint", "uint32" then [value].pack(big_endian ? "L>" : "L<")
    when "float", "float32" then [value].pack(big_endian ? "g" : "e")
    when "double", "float64" then [value].pack(big_endian ? "G" : "E")
    else
      raise "unsupported test scalar #{type}"
    end
  end

  it "parses a binary little-endian 3DGS PLY" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]

    set = described_class.parse_bytes(build_ply(properties, [row]))

    expect(set.kind).to eq(:gaussian3d)
    expect(set.items.length).to eq(1)
    expect(set.items.first.position).to eq([1.0, 2.0, 3.0])
    expect(set.items.first.sh[0]).to be_within(1e-6).of(0.7)
    expect(set.items.first.sh[1]).to be_within(1e-6).of(0.8)
    expect(set.items.first.sh[2]).to be_within(1e-6).of(0.9)
    expect(set.items.first.sh[3..]).to all(eq(0.0))
    expect(set.count).to eq(1)
    expect(set.statistics.bounds.min).to eq([1.0, 2.0, 3.0])
    expect(set.statistics.bounds.max).to eq([1.0, 2.0, 3.0])
    expect(set.statistics.opacity_min).to be_within(1e-6).of(0.4)
    expect(set.statistics.scale_max).to be_within(1e-6).of(0.3)
  end

  it "keeps PLY comments and obj_info as metadata" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]

    set = described_class.parse_bytes(
      build_ply(properties, [row], header_lines: ["comment source test", "obj_info train_iter 42"])
    )

    expect(set.metadata[:comments]).to eq(["source test"])
    expect(set.metadata[:obj_info]).to eq(["train_iter 42"])
  end

  it "parses gzip-compressed PLY files" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    file = Tempfile.new(["scene", ".notply"])
    file.binmode
    Zlib::GzipWriter.wrap(file) { |gzip| gzip.write(build_ply(properties, [row])) }

    set = described_class.parse_file(file.path)

    expect(set.kind).to eq(:gaussian3d)
    expect(set.count).to eq(1)
  ensure
    file&.close
    file&.unlink
  end

  it "can parse without retaining Gaussian objects" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    rows = [
      [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9],
      [-1.0, -2.0, -3.0, 0.5, 0.3, 0.2, 0.1, 1.0, 0.0, 0.0, 0.0, 0.6, 0.5, 0.4]
    ]

    set = described_class.parse_bytes(build_ply(properties, rows), retain_items: false)

    expect(set.items).to be_empty
    expect(set.count).to eq(2)
    expect(set.packed_bytes.bytesize).to eq(2 * ThreeDgcViewer::Gaussian.item_size(:gaussian3d))
    expect(set.statistics.bounds.min).to eq([-1.0, -2.0, -3.0])
    expect(set.statistics.bounds.max).to eq([1.0, 2.0, 3.0])
  end

  it "skips non-finite Gaussian rows and reports invalid count" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    rows = [
      [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9],
      [Float::NAN, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    ]

    set = described_class.parse_bytes(build_ply(properties, rows))

    expect(set.count).to eq(1)
    expect(set.items.length).to eq(1)
    expect(set.statistics.invalid_count).to eq(1)
  end

  it "parses ASCII PLY" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]

    set = described_class.parse_bytes(build_ply(properties, [row], format: "ascii"))

    expect(set.kind).to eq(:gaussian3d)
    expect(set.items.first.position).to eq([1.0, 2.0, 3.0])
    expect(set.items.first.sh[0]).to eq(0.7)
  end

  it "parses binary big-endian PLY" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]

    set = described_class.parse_bytes(build_ply(properties, [row], format: "binary_big_endian"))

    expect(set.kind).to eq(:gaussian3d)
    expect(set.items.first.position).to eq([1.0, 2.0, 3.0])
    expect(set.items.first.sh[2]).to be_within(1e-6).of(0.9)
  end

  it "detects missing required fields" do
    properties = [["float", "x"]]

    expect { described_class.parse_bytes(build_ply(properties, [[1.0]])) }
      .to raise_error(ThreeDgcViewer::PlyError, /unsupported|missing/)
  end

  it "rejects incomplete STG-Lite properties" do
    properties = (REQUIRED_3D + ["motion_0"]).map { |name| ["float", name] }
    row = Array.new(properties.length, 0.0)

    expect { described_class.parse_bytes(build_ply(properties, [row])) }
      .to raise_error(ThreeDgcViewer::PlyError, /unsupported|incomplete/)
  end

  it "reads all supported scalar types as numeric values" do
    properties = [
      ["char", "x"],
      ["uchar", "y"],
      ["short", "z"],
      ["ushort", "opacity"],
      ["int", "scale_0"],
      ["uint", "scale_1"],
      ["float", "scale_2"],
      ["double", "rot_0"],
      ["float", "rot_1"],
      ["float", "rot_2"],
      ["float", "rot_3"],
      ["float", "f_dc_0"],
      ["float", "f_dc_1"],
      ["float", "f_dc_2"]
    ]

    row = [-1, 2, -3, 4, -5, 6, 7.5, 1.0, 0.0, 0.0, 0.0, 0.1, 0.2, 0.3]
    item = described_class.parse_bytes(build_ply(properties, [row])).items.first

    expect(item.position).to eq([-1.0, 2.0, -3.0])
    expect(item.opacity).to eq(4.0)
    expect(item.scale).to eq([-5.0, 6.0, 7.5])
    expect(item.rotation).to eq([1.0, 0.0, 0.0, 0.0])
  end

  it "parses STG-Lite fields as Gaussian4d" do
    properties = (REQUIRED_3D + REQUIRED_STG).map { |name| ["float", name] }
    row = Array.new(properties.length) { |index| index.to_f }

    set = described_class.parse_bytes(build_ply(properties, [row]))
    item = set.items.first

    expect(set.kind).to eq(:gaussian4d)
    expect(item.motion_0).to eq([16.0, 17.0, 18.0])
    expect(item.motion_1).to eq([19.0, 20.0, 21.0])
    expect(item.motion_2).to eq([22.0, 23.0, 24.0])
    expect(item.omega).to eq([25.0, 26.0, 27.0, 28.0])
    expect(item.trbf_center).to eq(14.0)
    expect(item.trbf_scale).to eq(15.0)
    expect(item.base_color).to eq([11.0, 12.0, 13.0])
  end

  it "rejects list properties in vertex" do
    bytes = "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty list uchar int x\nend_header\n"

    expect { described_class.parse_bytes(bytes) }.to raise_error(ThreeDgcViewer::PlyError, /property list/)
  end

  it "rejects truncated bodies" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    bytes = build_ply(properties, [Array.new(properties.length, 0.0)])

    expect { described_class.parse_bytes(bytes.byteslice(0, bytes.bytesize - 1)) }
      .to raise_error(ThreeDgcViewer::PlyError, /too short/)
  end
end
