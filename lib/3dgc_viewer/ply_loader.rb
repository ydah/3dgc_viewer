# frozen_string_literal: true

require_relative "errors"
require_relative "gaussian"

module ThreeDgcViewer
  class PlyLoader
    REQUIRED_3DGS_FIELDS = %w[
      x y z opacity scale_0 scale_1 scale_2
      rot_0 rot_1 rot_2 rot_3
      f_dc_0 f_dc_1 f_dc_2
    ].freeze

    REQUIRED_STG_LITE_FIELDS = %w[
      trbf_center trbf_scale
      motion_0 motion_1 motion_2 motion_3 motion_4 motion_5 motion_6 motion_7 motion_8
      omega_0 omega_1 omega_2 omega_3
    ].freeze

    SCALAR_TYPES = {
      "char" => [:c, 1],
      "int8" => [:c, 1],
      "uchar" => [:C, 1],
      "uint8" => [:C, 1],
      "short" => [:s, 2],
      "int16" => [:s, 2],
      "ushort" => [:S, 2],
      "uint16" => [:S, 2],
      "int" => [:l, 4],
      "int32" => [:l, 4],
      "uint" => [:L, 4],
      "uint32" => [:L, 4],
      "float" => [:f, 4],
      "float32" => [:f, 4],
      "double" => [:d, 8],
      "float64" => [:d, 8]
    }.freeze

    Property = Struct.new(:name, :type, :offset, :size, keyword_init: true)
    Header = Struct.new(:format, :header_end, :vertex_count, :vertex_stride, :properties, keyword_init: true)

    def self.parse_file(path)
      parse_bytes(File.binread(path))
    end

    def self.parse_bytes(bytes)
      new(bytes.b).parse
    end

    def initialize(bytes)
      @bytes = bytes
    end

    def parse
      header = parse_header
      validate_body_size(header)

      kind = classify(header)
      case kind
      when :gaussian3d
        Gaussian::GaussianSet.new(kind: kind, items: parse_gaussian3d(header))
      when :gaussian4d
        Gaussian::GaussianSet.new(kind: kind, items: parse_gaussian4d(header))
      else
        raise PlyError, "unsupported or incomplete Gaussian PLY payload"
      end
    end

    private

    def parse_header
      marker = "end_header\n"
      marker_index = @bytes.index(marker)
      unless marker_index
        marker = "end_header\r\n"
        marker_index = @bytes.index(marker)
      end
      raise PlyError, "PLY header is missing end_header" unless marker_index

      header_end = marker_index + marker.bytesize
      header_text = @bytes.byteslice(0, header_end).dup.force_encoding(Encoding::UTF_8)
      raise PlyError, "PLY header is not valid UTF-8" unless header_text.valid_encoding?

      format = nil
      vertex_count = nil
      in_vertex = false
      offset = 0
      properties = []

      header_text.each_line do |line|
        tokens = line.strip.split(/\s+/)
        next if tokens.empty?

        case tokens[0]
        when "format"
          format = parse_format(tokens)
        when "element"
          in_vertex = tokens[1] == "vertex"
          vertex_count = parse_vertex_count(tokens) if in_vertex
        when "property"
          next unless in_vertex

          property = parse_property(tokens, offset)
          properties << property
          offset += property.size
        end
      end

      raise PlyError, "PLY format line is missing" unless format
      raise PlyError, "PLY format ascii is not supported" if format == :ascii
      raise PlyError, "PLY format binary_big_endian is not supported" if format == :binary_big_endian
      raise PlyError, "PLY element vertex is missing" unless vertex_count

      Header.new(
        format: format,
        header_end: header_end,
        vertex_count: vertex_count,
        vertex_stride: offset,
        properties: properties
      )
    end

    def parse_format(tokens)
      value = tokens[1]
      version = tokens[2]
      raise PlyError, "unsupported PLY format version: #{version.inspect}" unless version == "1.0"

      case value
      when "ascii" then :ascii
      when "binary_little_endian" then :binary_little_endian
      when "binary_big_endian" then :binary_big_endian
      else
        raise PlyError, "unsupported PLY format: #{value.inspect}"
      end
    end

    def parse_vertex_count(tokens)
      raise PlyError, "invalid element vertex line" unless tokens.length >= 3

      Integer(tokens[2], exception: false) || raise(PlyError, "invalid vertex count: #{tokens[2].inspect}")
    end

    def parse_property(tokens, offset)
      raise PlyError, "property list in vertex is not supported" if tokens[1] == "list"
      raise PlyError, "invalid property line" unless tokens.length >= 3

      scalar = SCALAR_TYPES[tokens[1]]
      raise PlyError, "unsupported PLY scalar type: #{tokens[1]}" unless scalar

      Property.new(name: tokens[2], type: scalar[0], offset: offset, size: scalar[1])
    end

    def validate_body_size(header)
      expected_body_size = header.vertex_count * header.vertex_stride
      expected_total_size = header.header_end + expected_body_size
      raise PlyError, "PLY body is too short" if @bytes.bytesize < expected_total_size
    end

    def classify(header)
      property_names = header.properties.map(&:name)
      has_3dgs_core = REQUIRED_3DGS_FIELDS.all? { |name| property_names.include?(name) }
      return :unknown unless has_3dgs_core

      has_any_stg = REQUIRED_STG_LITE_FIELDS.any? { |name| property_names.include?(name) }
      has_all_stg = REQUIRED_STG_LITE_FIELDS.all? { |name| property_names.include?(name) }

      if has_all_stg
        :gaussian4d
      elsif has_any_stg
        :unknown
      else
        :gaussian3d
      end
    end

    def parse_gaussian3d(header)
      require_properties(header, REQUIRED_3DGS_FIELDS)

      header.vertex_count.times.map do |index|
        base = header.header_end + (index * header.vertex_stride)
        sh = [
          read(header, base, "f_dc_0"),
          read(header, base, "f_dc_1"),
          read(header, base, "f_dc_2")
        ]
        45.times { |i| sh << read(header, base, "f_rest_#{i}", default: 0.0) }

        Gaussian::Gaussian3d.new(
          position: [read(header, base, "x"), read(header, base, "y"), read(header, base, "z")],
          opacity: read(header, base, "opacity"),
          scale: [read(header, base, "scale_0"), read(header, base, "scale_1"), read(header, base, "scale_2")],
          rotation: [
            read(header, base, "rot_0"),
            read(header, base, "rot_1"),
            read(header, base, "rot_2"),
            read(header, base, "rot_3")
          ],
          sh: sh
        )
      end
    end

    def parse_gaussian4d(header)
      require_properties(header, REQUIRED_3DGS_FIELDS + REQUIRED_STG_LITE_FIELDS)

      header.vertex_count.times.map do |index|
        base = header.header_end + (index * header.vertex_stride)
        motion = 9.times.map { |i| read(header, base, "motion_#{i}") }

        Gaussian::Gaussian4d.new(
          position: [read(header, base, "x"), read(header, base, "y"), read(header, base, "z")],
          opacity: read(header, base, "opacity"),
          scale: [read(header, base, "scale_0"), read(header, base, "scale_1"), read(header, base, "scale_2")],
          rotation: [
            read(header, base, "rot_0"),
            read(header, base, "rot_1"),
            read(header, base, "rot_2"),
            read(header, base, "rot_3")
          ],
          motion_0: motion[0, 3],
          motion_1: motion[3, 3],
          motion_2: motion[6, 3],
          omega: 4.times.map { |i| read(header, base, "omega_#{i}") },
          trbf_center: read(header, base, "trbf_center"),
          trbf_scale: read(header, base, "trbf_scale"),
          base_color: [
            read(header, base, "f_dc_0"),
            read(header, base, "f_dc_1"),
            read(header, base, "f_dc_2")
          ]
        )
      end
    end

    def require_properties(header, names)
      property_names = header.properties.map(&:name)
      missing = names.reject { |name| property_names.include?(name) }
      return if missing.empty?

      raise PlyError, "missing required PLY vertex properties: #{missing.join(", ")}"
    end

    def read(header, vertex_base, name, default: nil)
      property = header.properties.find { |candidate| candidate.name == name }
      return default unless property

      absolute_offset = vertex_base + property.offset
      chunk = @bytes.byteslice(absolute_offset, property.size)
      raise PlyError, "PLY body is too short" unless chunk&.bytesize == property.size

      unpack_scalar(chunk, property.type).to_f
    end

    def unpack_scalar(chunk, type)
      case type
      when :c then chunk.unpack1("c")
      when :C then chunk.unpack1("C")
      when :s then chunk.unpack1("s<")
      when :S then chunk.unpack1("S<")
      when :l then chunk.unpack1("l<")
      when :L then chunk.unpack1("L<")
      when :f then chunk.unpack1("e")
      when :d then chunk.unpack1("E")
      else
        raise PlyError, "unsupported scalar reader: #{type.inspect}"
      end
    end
  end
end
