# frozen_string_literal: true

require_relative "base_pass"
require_relative "../binary_pack"

module ThreeDgcViewer
  module Passes
    class TileRangePass < BasePass
      def initialize(**kwargs)
        super
        create_pipelines if gpu_enabled?
      end

      def recreate_bind_group(resources: @resources, **_kwargs)
        @resources = resources
        release
        @released = false
        @gpu_objects = []
        @shader_modules = {}
        create_pipelines if gpu_enabled?
      end

      def encode(encoder, resources: @resources)
        super
        if @clear_bundle
          encode_compute(encoder, @clear_bundle) { |pass| pass.dispatch_workgroups(ceil_div(resources.tile_count, 256), 1, 1) }
          encode_compute(encoder, @range_bundle) { |pass| pass.dispatch_workgroups_indirect(resources.tile_range_dispatch_args_buffer, offset: 0) }
          return
        end

        return unless encoder.respond_to?(:dispatch_compute)

        encoder.dispatch_compute("clear_tile_ranges.compute.wgsl", ceil_div(resources.tile_count, 256), 1, 1)
        encoder.dispatch_compute_indirect("tile_range.compute.wgsl", resources.tile_range_dispatch_args_buffer, 0) if encoder.respond_to?(:dispatch_compute_indirect)
      end

      private

      def create_pipelines
        @tile_range_params = static_buffer("Tile Range Params", BinaryPack.u32(@resources.tile_count), usage: [:uniform])
        @clear_bundle = compute_bundle(
          "clear_tile_ranges.compute.wgsl",
          layout_entries: [buffer_layout(0, type: :uniform), buffer_layout(1)],
          bind_entries: [buffer_entry(0, @tile_range_params), buffer_entry(1, @resources.tile_ranges_buffer)]
        )
        @range_bundle = compute_bundle(
          "tile_range.compute.wgsl",
          layout_entries: [
            buffer_layout(0, type: :read_only_storage),
            buffer_layout(1, type: :uniform),
            buffer_layout(2, type: :read_only_storage),
            buffer_layout(3)
          ],
          bind_entries: [
            buffer_entry(0, @resources.total_pairs_buffer),
            buffer_entry(1, @tile_range_params),
            buffer_entry(2, @resources.pair_keys_buffer),
            buffer_entry(3, @resources.tile_ranges_buffer)
          ]
        )
      end

      def ceil_div(value, divisor)
        (value + divisor - 1) / divisor
      end
    end
  end
end
