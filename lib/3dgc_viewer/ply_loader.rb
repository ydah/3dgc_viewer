# frozen_string_literal: true

require_relative "errors"
require_relative "gaussian"
require "stringio"
require "zlib"

module ThreeDgcViewer
  class PlyLoader
    MAX_HEADER_BYTES = 1 * 1024 * 1024
    MAX_VERTEX_COUNT = 100_000_000
    MAX_VERTEX_STRIDE = 64 * 1024
    MAX_ELEMENTS = 1024
    MAX_VERTEX_PROPERTIES = 512
    MAX_ELEMENT_PROPERTIES = 512
    MAX_ELEMENT_NAME_BYTES = 256
    MAX_PROPERTY_NAME_BYTES = 256
    MAX_LIST_VALUES = 1_000_000
    MAX_SH_DEGREE = 3
    SH_REST_COEFFICIENTS_PER_CHANNEL = 15

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

    PROPERTY_ALIASES = {
      "x" => %w[position_x pos_x],
      "y" => %w[position_y pos_y],
      "z" => %w[position_z pos_z],
      "opacity" => %w[alpha],
      "scale_0" => %w[scale_x sx],
      "scale_1" => %w[scale_y sy],
      "scale_2" => %w[scale_z sz],
      "rot_0" => %w[rotation_0 qw],
      "rot_1" => %w[rotation_1 qx],
      "rot_2" => %w[rotation_2 qy],
      "rot_3" => %w[rotation_3 qz],
      "f_dc_0" => %w[red r color_0 diffuse_red],
      "f_dc_1" => %w[green g color_1 diffuse_green],
      "f_dc_2" => %w[blue b color_2 diffuse_blue]
    }.freeze

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

    BodyProperty = Struct.new(
      :name, :type, :size, :list, :count_type, :count_size, :value_type, :value_size,
      keyword_init: true
    ) do
      def list?
        list
      end
    end
    Element = Struct.new(:name, :count, :properties, keyword_init: true)
    Property = Struct.new(:name, :type, :offset, :size, :index, keyword_init: true)
    Header = Struct.new(
      :format, :header_end, :vertex_count, :vertex_stride,
      :properties, :property_map, :property_alias_map, :elements, :comments, :obj_info, keyword_init: true
    )

    def self.parse_file(path, retain_items: true, sh_degree: MAX_SH_DEGREE,
                        max_vertex_count: MAX_VERTEX_COUNT, max_file_bytes: nil)
      validate_file_size(path, max_file_bytes)
      File.open(path, "rb") do |file|
        if gzip_io?(file)
          gzip = Zlib::GzipReader.new(file)
          begin
            new(gzip, retain_items: retain_items, sh_degree: sh_degree, max_vertex_count: max_vertex_count).parse
          ensure
            gzip.close
          end
        else
          new(file, retain_items: retain_items, sh_degree: sh_degree, max_vertex_count: max_vertex_count).parse
        end
      end
    end

    def self.parse_bytes(bytes, retain_items: true, sh_degree: MAX_SH_DEGREE,
                         max_vertex_count: MAX_VERTEX_COUNT, max_file_bytes: nil)
      byte_size = bytes.to_s.bytesize
      max_bytes = validate_max_file_bytes(max_file_bytes)
      raise PlyError, "PLY input size #{byte_size} exceeds max file bytes #{max_bytes}" if max_bytes && byte_size > max_bytes

      io = StringIO.new(bytes.b)
      if gzip_io?(io)
        gzip = Zlib::GzipReader.new(io)
        begin
          new(gzip, retain_items: retain_items, sh_degree: sh_degree, max_vertex_count: max_vertex_count).parse
        ensure
          gzip.close
        end
      else
        new(io, retain_items: retain_items, sh_degree: sh_degree, max_vertex_count: max_vertex_count).parse
      end
    end

    def self.gzip_io?(io)
      magic = io.read(2)
      io.rewind
      magic == "\x1F\x8B".b
    end

    def initialize(io, retain_items: true, sh_degree: MAX_SH_DEGREE, max_vertex_count: MAX_VERTEX_COUNT)
      @io = io
      @retain_items = retain_items
      @sh_degree = self.class.validate_sh_degree(sh_degree)
      @max_vertex_count = self.class.validate_max_vertex_count(max_vertex_count)
    end

    def self.validate_sh_degree(value)
      degree = Integer(value, exception: false)
      raise ArgumentError, "SH degree must be an integer from 0 to #{MAX_SH_DEGREE}" unless degree && degree.between?(0, MAX_SH_DEGREE)

      degree
    end

    def self.validate_max_vertex_count(value)
      count = Integer(value, exception: false)
      unless count && count.positive? && count <= MAX_VERTEX_COUNT
        raise ArgumentError, "max vertex count must be a positive integer up to #{MAX_VERTEX_COUNT}"
      end

      count
    end

    def self.validate_max_file_bytes(value)
      return nil if value.nil?

      count = Integer(value, exception: false)
      raise ArgumentError, "max file bytes must be a positive integer" unless count&.positive?

      count
    end

    def self.validate_file_size(path, max_file_bytes)
      max_bytes = validate_max_file_bytes(max_file_bytes)
      return unless max_bytes

      size = File.size(path)
      raise PlyError, "PLY file size #{size} exceeds max file bytes #{max_bytes}" if size > max_bytes
    end

    def parse
      header = parse_header
      validate_body_size(header)

      kind = classify(header)
      case kind
      when :gaussian3d
        parse_gaussian3d(header)
      when :gaussian4d
        parse_gaussian4d(header)
      else
        raise PlyError, "unsupported or incomplete Gaussian PLY payload"
      end
    end

    private

    def parse_header
      header_text = +""
      header_end = 0

      while (line = @io.gets)
        header_text << line
        header_end += line.bytesize
        raise PlyError, "PLY header exceeds #{MAX_HEADER_BYTES} bytes" if header_end > MAX_HEADER_BYTES
        break if line.strip == "end_header"
      end

      raise PlyError, "PLY header is missing end_header" unless header_text.lines.last&.strip == "end_header"

      header_text = header_text.dup.force_encoding(Encoding::UTF_8)
      raise PlyError, "PLY header is not valid UTF-8" unless header_text.valid_encoding?

      lines = header_text.each_line
      first_line = lines.next&.strip
      raise PlyError, "PLY header must start with ply" unless first_line == "ply"

      format = nil
      vertex_count = nil
      in_vertex = false
      offset = 0
      properties = []
      property_map = {}
      elements = []
      current_element = nil
      comments = []
      obj_info = []

      lines.each do |line|
        tokens = line.strip.split(/\s+/)
        next if tokens.empty?

        case tokens[0]
        when "comment"
          comments << line.sub(/\A\s*comment\s?/, "").strip
        when "obj_info"
          obj_info << line.sub(/\A\s*obj_info\s?/, "").strip
        when "format"
          format = parse_format(tokens)
        when "element"
          raise PlyError, "too many PLY elements" if elements.length >= MAX_ELEMENTS

          current_element = parse_element(tokens)
          elements << current_element
          in_vertex = current_element.name == "vertex"
          if in_vertex
            raise PlyError, "duplicate PLY vertex element" if vertex_count

            vertex_count = current_element.count
            if vertex_count > @max_vertex_count
              raise PlyError, "PLY vertex count #{vertex_count} exceeds max gaussians #{@max_vertex_count}"
            end
            offset = 0
          end
        when "property"
          raise PlyError, "PLY property appears before any element" unless current_element
          if in_vertex
            raise PlyError, "too many PLY vertex properties" if current_element.properties.length >= MAX_VERTEX_PROPERTIES
          elsif current_element.properties.length >= MAX_ELEMENT_PROPERTIES
            raise PlyError, "too many PLY properties for element #{current_element.name}"
          end

          body_property = parse_body_property(tokens)
          current_element.properties << body_property
          next unless in_vertex

          property = parse_property(tokens, offset, properties.length)
          raise PlyError, "duplicate PLY vertex property: #{property.name}" if property_map.key?(property.name)
          raise PlyError, "too many PLY vertex properties" if properties.length >= MAX_VERTEX_PROPERTIES

          properties << property
          property_map[property.name] = property
          offset += property.size
          raise PlyError, "PLY vertex stride exceeds #{MAX_VERTEX_STRIDE} bytes" if offset > MAX_VERTEX_STRIDE
        end
      end

      raise PlyError, "PLY format line is missing" unless format
      raise PlyError, "PLY element vertex is missing" unless vertex_count

      Header.new(
        format: format,
        header_end: header_end,
        vertex_count: vertex_count,
        vertex_stride: offset,
        properties: properties,
        property_map: property_map,
        property_alias_map: build_property_alias_map(property_map),
        elements: elements,
        comments: comments,
        obj_info: obj_info
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

    def parse_element(tokens)
      raise PlyError, "invalid element line" unless tokens.length == 3

      name = tokens[1]
      raise PlyError, "PLY element name is too long" if name.bytesize > MAX_ELEMENT_NAME_BYTES
      count = Integer(tokens[2], exception: false) || raise(PlyError, "invalid element count: #{tokens[2].inspect}")
      raise PlyError, "element count must be non-negative" if count.negative?
      raise PlyError, "element count exceeds #{MAX_VERTEX_COUNT}" if count > MAX_VERTEX_COUNT

      Element.new(name: name, count: count, properties: [])
    end

    def parse_body_property(tokens)
      if tokens[1] == "list"
        raise PlyError, "invalid list property line" unless tokens.length == 5

        count_scalar = SCALAR_TYPES[tokens[2]]
        value_scalar = SCALAR_TYPES[tokens[3]]
        raise PlyError, "unsupported PLY list count type: #{tokens[2]}" unless count_scalar
        raise PlyError, "unsupported PLY list value type: #{tokens[3]}" unless value_scalar
        raise PlyError, "PLY property name is too long" if tokens[4].bytesize > MAX_PROPERTY_NAME_BYTES

        return BodyProperty.new(
          name: tokens[4],
          list: true,
          count_type: count_scalar[0],
          count_size: count_scalar[1],
          value_type: value_scalar[0],
          value_size: value_scalar[1]
        )
      end

      raise PlyError, "invalid property line" unless tokens.length == 3

      scalar = SCALAR_TYPES[tokens[1]]
      raise PlyError, "unsupported PLY scalar type: #{tokens[1]}" unless scalar
      raise PlyError, "PLY property name is too long" if tokens[2].bytesize > MAX_PROPERTY_NAME_BYTES

      BodyProperty.new(name: tokens[2], type: scalar[0], size: scalar[1], list: false)
    end

    def parse_property(tokens, offset, index)
      raise PlyError, "property list in vertex is not supported" if tokens[1] == "list"
      raise PlyError, "invalid property line" unless tokens.length == 3

      scalar = SCALAR_TYPES[tokens[1]]
      raise PlyError, "unsupported PLY scalar type: #{tokens[1]}" unless scalar

      raise PlyError, "PLY property name is too long" if tokens[2].bytesize > MAX_PROPERTY_NAME_BYTES

      Property.new(name: tokens[2], type: scalar[0], offset: offset, size: scalar[1], index: index)
    end

    def validate_body_size(header)
      return if header.format == :ascii

      expected_body_size = fixed_binary_body_size(header)
      return unless expected_body_size

      expected_total_size = header.header_end + expected_body_size
      return unless @io.respond_to?(:size)

      actual_total_size = @io.size
      actual_body_size = actual_total_size - header.header_end
      return if actual_total_size == expected_total_size

      if actual_total_size > expected_total_size
        raise PlyError,
          "PLY body has trailing bytes: expected #{expected_body_size} body bytes " \
          "(#{expected_total_size} total), got #{actual_body_size} body bytes (#{actual_total_size} total)"
      end

      raise PlyError,
        "PLY body is too short: expected at least #{expected_body_size} body bytes " \
        "(#{expected_total_size} total), got #{actual_body_size} body bytes (#{actual_total_size} total)"
    end

    def fixed_binary_body_size(header)
      header.elements.sum do |element|
        row_size = element.properties.sum do |property|
          return nil if property.list?

          property.size
        end
        element.count * row_size
      end
    end

    def classify(header)
      missing_core = missing_properties(header, REQUIRED_3DGS_FIELDS)
      if missing_core.any?
        present_core_count = REQUIRED_3DGS_FIELDS.length - missing_core.length
        return :unknown if present_core_count.zero?

        raise_missing_properties(missing_core)
      end

      has_any_stg = REQUIRED_STG_LITE_FIELDS.any? { |name| property_for(header, name) }
      missing_stg = missing_properties(header, REQUIRED_STG_LITE_FIELDS)

      if missing_stg.empty?
        :gaussian4d
      elsif has_any_stg
        raise PlyError, "incomplete STG-Lite PLY payload; missing required PLY vertex properties: #{missing_stg.join(", ")}"
      else
        :gaussian3d
      end
    end

    def parse_gaussian3d(header)
      require_properties(header, REQUIRED_3DGS_FIELDS)
      skip_elements_before_vertex(header)

      items = @retain_items ? [] : nil
      packed = Gaussian.packed_buffer(:gaussian3d, header.vertex_count)
      statistics = StatisticsBuilder.new
      row_unpack_directive = vertex_row_unpack_directive(header)

      header.vertex_count.times do |index|
        row = read_row(header, index, row_unpack_directive)
        sh = [
          read(header, row, "f_dc_0", vertex_index: index),
          read(header, row, "f_dc_1", vertex_index: index),
          read(header, row, "f_dc_2", vertex_index: index)
        ]
        45.times do |i|
          sh << if keep_sh_rest_coefficient?(i)
                  read(header, row, "f_rest_#{i}", default: 0.0, vertex_index: index)
                else
                  0.0
                end
        end

        position = [
          read(header, row, "x", vertex_index: index),
          read(header, row, "y", vertex_index: index),
          read(header, row, "z", vertex_index: index)
        ]
        opacity = read(header, row, "opacity", vertex_index: index)
        scale = [
          read(header, row, "scale_0", vertex_index: index),
          read(header, row, "scale_1", vertex_index: index),
          read(header, row, "scale_2", vertex_index: index)
        ]
        rotation = [
          read(header, row, "rot_0", vertex_index: index),
          read(header, row, "rot_1", vertex_index: index),
          read(header, row, "rot_2", vertex_index: index),
          read(header, row, "rot_3", vertex_index: index)
        ]

        unless gaussian_finite?(position, [opacity], scale, rotation, sh)
          statistics.record_invalid
          next
        end

        statistics.record(position: position, opacity: opacity, scale: scale)
        if items
          item = Gaussian::Gaussian3d.new(
            position: position,
            opacity: opacity,
            scale: scale,
            rotation: rotation,
            sh: sh
          )
          items << item
          packed << item.pack
        else
          packed << Gaussian.pack_3d(position: position, opacity: opacity, scale: scale, rotation: rotation, sh: sh)
        end
      end

      gaussian_set(:gaussian3d, items, packed, statistics, header)
    end

    def parse_gaussian4d(header)
      require_properties(header, REQUIRED_3DGS_FIELDS + REQUIRED_STG_LITE_FIELDS)
      skip_elements_before_vertex(header)

      items = @retain_items ? [] : nil
      packed = Gaussian.packed_buffer(:gaussian4d, header.vertex_count)
      statistics = StatisticsBuilder.new
      row_unpack_directive = vertex_row_unpack_directive(header)

      header.vertex_count.times do |index|
        row = read_row(header, index, row_unpack_directive)
        motion = 9.times.map { |i| read(header, row, "motion_#{i}", vertex_index: index) }
        position = [
          read(header, row, "x", vertex_index: index),
          read(header, row, "y", vertex_index: index),
          read(header, row, "z", vertex_index: index)
        ]
        opacity = read(header, row, "opacity", vertex_index: index)
        scale = [
          read(header, row, "scale_0", vertex_index: index),
          read(header, row, "scale_1", vertex_index: index),
          read(header, row, "scale_2", vertex_index: index)
        ]
        rotation = [
          read(header, row, "rot_0", vertex_index: index),
          read(header, row, "rot_1", vertex_index: index),
          read(header, row, "rot_2", vertex_index: index),
          read(header, row, "rot_3", vertex_index: index)
        ]
        omega = 4.times.map { |i| read(header, row, "omega_#{i}", vertex_index: index) }
        trbf_center = read(header, row, "trbf_center", vertex_index: index)
        trbf_scale = read(header, row, "trbf_scale", vertex_index: index)
        base_color = [
          read(header, row, "f_dc_0", vertex_index: index),
          read(header, row, "f_dc_1", vertex_index: index),
          read(header, row, "f_dc_2", vertex_index: index)
        ]

        unless gaussian_finite?(position, [opacity], scale, rotation, motion, omega, [trbf_center, trbf_scale], base_color)
          statistics.record_invalid
          next
        end

        motion_0 = motion[0, 3]
        motion_1 = motion[3, 3]
        motion_2 = motion[6, 3]
        statistics.record(position: position, opacity: opacity, scale: scale)
        if items
          item = Gaussian::Gaussian4d.new(
            position: position,
            opacity: opacity,
            scale: scale,
            rotation: rotation,
            motion_0: motion_0,
            motion_1: motion_1,
            motion_2: motion_2,
            omega: omega,
            trbf_center: trbf_center,
            trbf_scale: trbf_scale,
            base_color: base_color
          )
          items << item
          packed << item.pack
        else
          packed << Gaussian.pack_4d(
            position: position,
            opacity: opacity,
            scale: scale,
            rotation: rotation,
            motion_0: motion_0,
            motion_1: motion_1,
            motion_2: motion_2,
            omega: omega,
            trbf_center: trbf_center,
            trbf_scale: trbf_scale,
            base_color: base_color
          )
        end
      end

      gaussian_set(:gaussian4d, items, packed, statistics, header)
    end

    def require_properties(header, names)
      missing = missing_properties(header, names)
      return if missing.empty?

      raise_missing_properties(missing)
    end

    def missing_properties(header, names)
      names.reject { |name| property_for(header, name) }
    end

    def raise_missing_properties(missing)
      raise PlyError, "missing required PLY vertex properties: #{missing.join(", ")}"
    end

    def keep_sh_rest_coefficient?(rest_index)
      harmonic_index = (rest_index % SH_REST_COEFFICIENTS_PER_CHANNEL) + 1
      harmonic_index < ((@sh_degree + 1) * (@sh_degree + 1))
    end

    def skip_elements_before_vertex(header)
      header.elements.each do |element|
        return if element.name == "vertex"

        skip_element(element, header.format)
      end
    end

    def skip_element(element, format)
      element.count.times do |index|
        if format == :ascii
          line = @io.gets
          raise PlyError, "PLY body is too short while skipping #{element.name} at row #{index}" unless line
          next
        end

        element.properties.each do |property|
          skip_body_property(property, format, element.name, index)
        end
      end
    end

    def skip_body_property(property, format, element_name, row_index)
      unless property.list?
        skip_bytes(property.size, "while skipping #{element_name} at row #{row_index}")
        return
      end

      count_chunk = read_exact(property.count_size, "while reading #{element_name}.#{property.name} list count at row #{row_index}")
      count = unpack_scalar(count_chunk, property.count_type, format).to_i
      raise PlyError, "negative PLY list count for #{element_name}.#{property.name} at row #{row_index}" if count.negative?
      if count > MAX_LIST_VALUES
        raise PlyError, "PLY list count for #{element_name}.#{property.name} at row #{row_index} exceeds #{MAX_LIST_VALUES}"
      end

      skip_bytes(count * property.value_size, "while skipping #{element_name}.#{property.name} list values at row #{row_index}")
    end

    def skip_bytes(size, context)
      return if size.zero?

      read_exact(size, context)
    end

    def read_exact(size, context)
      bytes = @io.read(size)
      return bytes if bytes&.bytesize == size

      raise PlyError, "PLY body is too short #{context}"
    end

    def read(header, row, name, default: nil, vertex_index: nil)
      property = property_for(header, name)
      return default unless property

      if header.format == :ascii
        return normalize_alias_value(name, property, unpack_ascii_scalar(row[property.index], property.type, name, vertex_index).to_f)
      end

      if row.is_a?(Array)
        value = row[property.index]
        raise PlyError, "PLY body is too short at vertex #{vertex_index}" if value.nil?

        return normalize_alias_value(name, property, value.to_f)
      end

      chunk = row.byteslice(property.offset, property.size)
      raise PlyError, "PLY body is too short at vertex #{vertex_index}" unless chunk&.bytesize == property.size

      normalize_alias_value(name, property, unpack_scalar(chunk, property.type, header.format).to_f)
    end

    def property_for(header, name)
      header.property_map[name] || header.property_alias_map[name]
    end

    def build_property_alias_map(property_map)
      PROPERTY_ALIASES.each_with_object({}) do |(canonical_name, aliases), alias_map|
        property = aliases.lazy.map { |alias_name| property_map[alias_name] }.find { |candidate| candidate }
        alias_map[canonical_name] = property if property
      end
    end

    def normalize_alias_value(requested_name, property, value)
      return value unless requested_name.start_with?("f_dc_")
      return value if property.name == requested_name
      return value unless value > 1.0

      value / 255.0
    end

    def read_row(header, index, unpack_directive = nil)
      return read_ascii_row(header, index) if header.format == :ascii

      row = @io.read(header.vertex_stride)
      return unpack_directive ? row.unpack(unpack_directive) : row if row&.bytesize == header.vertex_stride

      raise PlyError, "PLY body is too short at vertex #{index}"
    end

    def vertex_row_unpack_directive(header)
      return nil if header.format == :ascii
      return nil unless header.properties.all? { |property| property.type == :f }
      return nil unless header.vertex_stride == header.properties.length * 4

      header.format == :binary_big_endian ? "g*" : "e*"
    end

    def read_ascii_row(header, index)
      line = @io.gets
      raise PlyError, "PLY body is too short at vertex #{index}" unless line

      values = line.strip.split(/\s+/)
      if values.length < header.properties.length
        raise PlyError, "PLY ASCII row has too few values at vertex #{index}"
      end

      values
    end

    def gaussian_finite?(*groups)
      groups.flatten.all? { |value| value.to_f.finite? }
    end

    def gaussian_set(kind, items, packed, statistics, header)
      count = statistics.count
      Gaussian::GaussianSet.new(
        kind: kind,
        items: items || [],
        count: count,
        packed_bytes: packed,
        statistics: statistics.to_statistics,
        metadata: {comments: header.comments, obj_info: header.obj_info, sh_degree: @sh_degree}
      )
    end

    def unpack_ascii_scalar(token, type, property_name, vertex_index)
      value =
        case type
        when :c, :C, :s, :S, :l, :L
          Integer(token, exception: false)
        when :f, :d
          Float(token, exception: false)
        else
          raise PlyError, "unsupported scalar reader: #{type.inspect}"
        end
      return value if value

      raise PlyError, "invalid ASCII PLY value for #{property_name} at vertex #{vertex_index}: #{token.inspect}"
    end

    def unpack_scalar(chunk, type, format)
      big_endian = format == :binary_big_endian
      case type
      when :c then chunk.unpack1("c")
      when :C then chunk.unpack1("C")
      when :s then chunk.unpack1(big_endian ? "s>" : "s<")
      when :S then chunk.unpack1(big_endian ? "S>" : "S<")
      when :l then chunk.unpack1(big_endian ? "l>" : "l<")
      when :L then chunk.unpack1(big_endian ? "L>" : "L<")
      when :f then chunk.unpack1(big_endian ? "g" : "e")
      when :d then chunk.unpack1(big_endian ? "G" : "E")
      else
        raise PlyError, "unsupported scalar reader: #{type.inspect}"
      end
    end

    class StatisticsBuilder
      attr_reader :count

      def initialize
        @count = 0
        @invalid_count = 0
        @min = nil
        @max = nil
        @opacity_min = nil
        @opacity_max = nil
        @scale_min = nil
        @scale_max = nil
      end

      def record(position:, opacity:, scale:)
        @count += 1
        record_bounds(position)
        @opacity_min = [@opacity_min || opacity, opacity].min
        @opacity_max = [@opacity_max || opacity, opacity].max
        scale.each do |value|
          @scale_min = [@scale_min || value, value].min
          @scale_max = [@scale_max || value, value].max
        end
      end

      def record_invalid
        @invalid_count += 1
      end

      def to_statistics
        Gaussian::Statistics.new(
          count: @count,
          bounds: Gaussian::Bounds.new(min: @min, max: @max),
          opacity_min: @opacity_min,
          opacity_max: @opacity_max,
          scale_min: @scale_min,
          scale_max: @scale_max,
          invalid_count: @invalid_count
        )
      end

      private

      def record_bounds(position)
        @min ||= position.dup
        @max ||= position.dup
        3.times do |axis|
          @min[axis] = [@min[axis], position[axis]].min
          @max[axis] = [@max[axis], position[axis]].max
        end
      end
    end
  end
end
