# frozen_string_literal: true

require_relative "binary_pack"

module ThreeDgcViewer
  module Gaussian
    SH_COUNT = 48
    PREFIX_DISPATCH_ARGS_COUNT = 5
    RADIX_SORT_BINS = 256
    RADIX_SORT_PASSES = 8
    MAX_RADIX_WORKGROUPS = 256

    Bounds = Struct.new(:min, :max, keyword_init: true) do
      def self.empty
        new(min: nil, max: nil)
      end

      def empty?
        min.nil? || max.nil?
      end

      def center
        return [0.0, 0.0, 0.0] if empty?

        [
          (min[0] + max[0]) * 0.5,
          (min[1] + max[1]) * 0.5,
          (min[2] + max[2]) * 0.5
        ]
      end

      def radius
        return 1.0 if empty?

        dx = max[0] - min[0]
        dy = max[1] - min[1]
        dz = max[2] - min[2]
        [Math.sqrt((dx * dx) + (dy * dy) + (dz * dz)) * 0.5, 0.01].max
      end
    end

    Statistics = Struct.new(
      :count, :bounds, :opacity_min, :opacity_max,
      :scale_min, :scale_max, :invalid_count,
      keyword_init: true
    ) do
      def self.empty
        new(
          count: 0,
          bounds: Bounds.empty,
          opacity_min: nil,
          opacity_max: nil,
          scale_min: nil,
          scale_max: nil,
          invalid_count: 0
        )
      end
    end

    GaussianSet = Struct.new(:kind, :items, :count, :packed_bytes, :statistics, :metadata, keyword_init: true) do
      def initialize(kind:, items: [], count: nil, packed_bytes: nil, statistics: nil, metadata: nil)
        super(
          kind: kind,
          items: items || [],
          count: count || (items || []).length,
          packed_bytes: packed_bytes,
          statistics: statistics || Statistics.empty,
          metadata: metadata || {}
        )
      end
    end

    Gaussian3d = Struct.new(:position, :opacity, :scale, :rotation, :sh, keyword_init: true) do
      def pack
        Gaussian.pack_3d(position: position, opacity: opacity, scale: scale, rotation: rotation, sh: sh)
      end
    end

    Gaussian4d = Struct.new(
      :position, :opacity, :scale, :rotation,
      :motion_0, :motion_1, :motion_2,
      :omega, :trbf_center, :trbf_scale, :base_color,
      keyword_init: true
    ) do
      def pack
        Gaussian.pack_4d(
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

    module_function

    def pack_3d(position:, opacity:, scale:, rotation:, sh:)
      sh_values = Array(sh || []).first(SH_COUNT)
      sh_values += Array.new(SH_COUNT - sh_values.length, 0.0)

      BinaryPack.concat(
        BinaryPack.f32(position[0], position[1], position[2], opacity),
        BinaryPack.f32(scale[0], scale[1], scale[2]),
        BinaryPack.u32(0),
        BinaryPack.f32(rotation[0], rotation[1], rotation[2], rotation[3]),
        BinaryPack.f32(sh_values)
      )
    end

    def pack_4d(position:, opacity:, scale:, rotation:, motion_0:, motion_1:, motion_2:,
                omega:, trbf_center:, trbf_scale:, base_color:)
      BinaryPack.concat(
        BinaryPack.f32(position[0], position[1], position[2], opacity),
        BinaryPack.f32(scale[0], scale[1], scale[2]),
        BinaryPack.u32(0),
        BinaryPack.f32(rotation[0], rotation[1], rotation[2], rotation[3]),
        BinaryPack.f32(motion_0[0], motion_0[1], motion_0[2]),
        BinaryPack.u32(0),
        BinaryPack.f32(motion_1[0], motion_1[1], motion_1[2]),
        BinaryPack.u32(0),
        BinaryPack.f32(motion_2[0], motion_2[1], motion_2[2]),
        BinaryPack.u32(0),
        BinaryPack.f32(omega[0], omega[1], omega[2], omega[3]),
        BinaryPack.f32(trbf_center, trbf_scale),
        BinaryPack.u32(0, 0),
        BinaryPack.f32(base_color[0], base_color[1], base_color[2]),
        BinaryPack.u32(0)
      )
    end

    def pack_set(gaussian_set)
      return gaussian_set.packed_bytes.b if gaussian_set.packed_bytes

      gaussian_set.items.each_with_object(+"".b) { |item, buffer| buffer << item.pack }
    end

    def item_size(kind)
      case kind
      when :gaussian3d then 240
      when :gaussian4d then 144
      else
        raise ArgumentError, "unknown Gaussian kind: #{kind.inspect}"
      end
    end
  end
end
