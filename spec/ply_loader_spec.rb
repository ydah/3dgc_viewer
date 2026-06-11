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

  it "rejects PLY files above the configured vertex limit" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    rows = [
      [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9],
      [-1.0, -2.0, -3.0, 0.5, 0.3, 0.2, 0.1, 1.0, 0.0, 0.0, 0.0, 0.6, 0.5, 0.4]
    ]

    expect { described_class.parse_bytes(build_ply(properties, rows), max_vertex_count: 1) }
      .to raise_error(ThreeDgcViewer::PlyError, /vertex count 2 exceeds max gaussians 1/)
  end

  it "rejects inputs above the configured file byte limit" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    bytes = build_ply(properties, [[1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]])

    expect { described_class.parse_bytes(bytes, max_file_bytes: bytes.bytesize - 1) }
      .to raise_error(ThreeDgcViewer::PlyError, /input size .* exceeds max file bytes/)
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

  it "skips scalar non-vertex elements before ASCII vertices" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    header = +"ply\nformat ascii 1.0\n"
    header << "element camera 1\nproperty float focal\n"
    header << "element vertex 1\n"
    properties.each { |type, name| header << "property #{type} #{name}\n" }
    header << "end_header\n"
    bytes = "#{header}35.0\n#{row.join(" ")}\n"

    set = described_class.parse_bytes(bytes)

    expect(set.kind).to eq(:gaussian3d)
    expect(set.items.first.position).to eq([1.0, 2.0, 3.0])
  end

  it "skips list non-vertex elements before binary vertices" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    header = +"ply\nformat binary_little_endian 1.0\n"
    header << "element face 1\nproperty list uchar int vertex_indices\n"
    header << "element vertex 1\n"
    properties.each { |type, name| header << "property #{type} #{name}\n" }
    header << "end_header\n"
    face = [3].pack("C") + [0, 1, 2].pack("l<*")
    vertex = properties.each_with_index.map { |(type, _name), index| pack_scalar(type, row[index]) }.join

    set = described_class.parse_bytes((header + face + vertex).b)

    expect(set.kind).to eq(:gaussian3d)
    expect(set.items.first.position).to eq([1.0, 2.0, 3.0])
  end

  it "rejects excessive non-vertex list counts before allocating skip buffers" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    header = +"ply\nformat binary_little_endian 1.0\n"
    header << "element face 1\nproperty list uint int vertex_indices\n"
    header << "element vertex 1\n"
    properties.each { |type, name| header << "property #{type} #{name}\n" }
    header << "end_header\n"
    bytes = header.b + [described_class::MAX_LIST_VALUES + 1].pack("L<")

    expect { described_class.parse_bytes(bytes) }
      .to raise_error(ThreeDgcViewer::PlyError, /list count.*exceeds/)
  end

  it "parses common property aliases and RGB color fallback" do
    properties = [
      ["float", "position_x"],
      ["float", "position_y"],
      ["float", "position_z"],
      ["float", "alpha"],
      ["float", "scale_x"],
      ["float", "scale_y"],
      ["float", "scale_z"],
      ["float", "qw"],
      ["float", "qx"],
      ["float", "qy"],
      ["float", "qz"],
      ["uchar", "red"],
      ["uchar", "green"],
      ["uchar", "blue"]
    ]
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 255, 128, 0]

    item = described_class.parse_bytes(build_ply(properties, [row])).items.first

    expect(item.position).to eq([1.0, 2.0, 3.0])
    expect(item.opacity).to be_within(1e-6).of(0.4)
    expect(item.scale[0]).to be_within(1e-6).of(0.1)
    expect(item.scale[1]).to be_within(1e-6).of(0.2)
    expect(item.scale[2]).to be_within(1e-6).of(0.3)
    expect(item.rotation).to eq([1.0, 0.0, 0.0, 0.0])
    expect(item.sh[0]).to eq(1.0)
    expect(item.sh[1]).to be_within(1e-6).of(128.0 / 255.0)
    expect(item.sh[2]).to eq(0.0)
  end

  it "limits parsed SH rest coefficients by degree" do
    properties = REQUIRED_3D.map { |name| ["float", name] } +
      45.times.map { |index| ["float", "f_rest_#{index}"] }
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9] +
      45.times.map { |index| (index + 1).to_f }

    set = described_class.parse_bytes(build_ply(properties, [row]), sh_degree: 1)
    sh = set.items.first.sh

    expect(sh[3]).to eq(1.0)
    expect(sh[5]).to eq(3.0)
    expect(sh[6]).to eq(0.0)
    expect(sh[18]).to eq(16.0)
    expect(sh[21]).to eq(0.0)
    expect(sh[33]).to eq(31.0)
    expect(sh[36]).to eq(0.0)
    expect(set.metadata[:sh_degree]).to eq(1)
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

  it "parses required 3DGS properties regardless of vertex property order" do
    ordered_values = {
      "x" => 1.0,
      "y" => 2.0,
      "z" => 3.0,
      "opacity" => 0.4,
      "scale_0" => 0.1,
      "scale_1" => 0.2,
      "scale_2" => 0.3,
      "rot_0" => 1.0,
      "rot_1" => 0.0,
      "rot_2" => 0.0,
      "rot_3" => 0.0,
      "f_dc_0" => 0.7,
      "f_dc_1" => 0.8,
      "f_dc_2" => 0.9
    }
    properties = REQUIRED_3D.reverse.map { |name| ["float", name] }
    row = properties.map { |_type, name| ordered_values.fetch(name) }

    item = described_class.parse_bytes(build_ply(properties, [row])).items.first

    expect(item.position).to eq([1.0, 2.0, 3.0])
    expect(item.scale[0]).to be_within(1e-6).of(0.1)
    expect(item.scale[1]).to be_within(1e-6).of(0.2)
    expect(item.scale[2]).to be_within(1e-6).of(0.3)
    expect(item.sh[0]).to be_within(1e-6).of(0.7)
    expect(item.sh[1]).to be_within(1e-6).of(0.8)
    expect(item.sh[2]).to be_within(1e-6).of(0.9)
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

  it "rejects oversized PLY headers" do
    bytes = "ply\ncomment #{"x" * described_class::MAX_HEADER_BYTES}\n".b

    expect { described_class.parse_bytes(bytes) }
      .to raise_error(ThreeDgcViewer::PlyError, /header exceeds/)
  end

  it "rejects excessively long PLY property names" do
    name = "x" * (described_class::MAX_PROPERTY_NAME_BYTES + 1)
    bytes = "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float #{name}\nend_header\n"

    expect { described_class.parse_bytes(bytes) }
      .to raise_error(ThreeDgcViewer::PlyError, /property name is too long/)
  end

  it "rejects excessively long PLY element names" do
    name = "x" * (described_class::MAX_ELEMENT_NAME_BYTES + 1)
    bytes = "ply\nformat binary_little_endian 1.0\nelement #{name} 0\nend_header\n"

    expect { described_class.parse_bytes(bytes) }
      .to raise_error(ThreeDgcViewer::PlyError, /element name is too long/)
  end

  it "rejects excessive PLY element counts" do
    header = +"ply\nformat binary_little_endian 1.0\n"
    (described_class::MAX_ELEMENTS + 1).times do |index|
      header << "element ignored_#{index} 0\n"
    end
    header << "end_header\n"

    expect { described_class.parse_bytes(header.b) }
      .to raise_error(ThreeDgcViewer::PlyError, /too many PLY elements/)
  end

  it "rejects excessive non-vertex PLY property counts" do
    header = +"ply\nformat binary_little_endian 1.0\nelement camera 1\n"
    (described_class::MAX_ELEMENT_PROPERTIES + 1).times do |index|
      header << "property float p_#{index}\n"
    end
    header << "element vertex 0\nend_header\n"

    expect { described_class.parse_bytes(header.b) }
      .to raise_error(ThreeDgcViewer::PlyError, /too many PLY properties for element camera/)
  end

  it "rejects malformed PLY property lines with trailing tokens" do
    bytes = "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x trailing\nend_header\n"

    expect { described_class.parse_bytes(bytes.b) }
      .to raise_error(ThreeDgcViewer::PlyError, /invalid property line/)
  end

  it "rejects excessive PLY vertex property counts" do
    header = +"ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
    (described_class::MAX_VERTEX_PROPERTIES + 1).times do |index|
      header << "property float p_#{index}\n"
    end
    header << "end_header\n"

    expect { described_class.parse_bytes(header.b) }
      .to raise_error(ThreeDgcViewer::PlyError, /too many PLY vertex properties/)
  end

  it "rejects truncated bodies" do
    properties = REQUIRED_3D.map { |name| ["float", name] }
    bytes = build_ply(properties, [Array.new(properties.length, 0.0)])

    expect { described_class.parse_bytes(bytes.byteslice(0, bytes.bytesize - 1)) }
      .to raise_error(ThreeDgcViewer::PlyError, /expected at least .* body bytes/)
  end
end
