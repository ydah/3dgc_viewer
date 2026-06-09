# frozen_string_literal: true

require_relative "base_pass"
require_relative "../binary_pack"

module ThreeDgcViewer
  module Passes
    class PrefixScanPass < BasePass
      STEPS = [
        [:dispatch, "build_dispatch_args.compute.wgsl", 1, 1, 1],
        [:indirect, "scan_exclusive_level.compute.wgsl", 0],
        [:indirect, "scan_exclusive_level.compute.wgsl", 16],
        [:indirect, "scan_exclusive_level.compute.wgsl", 32],
        [:indirect, "add_block_offsets.compute.wgsl", 48],
        [:indirect, "add_block_offsets.compute.wgsl", 64],
        [:dispatch, "build_total_pairs.compute.wgsl", 1, 1, 1]
      ].freeze

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
        if @build_dispatch_bundle
          encode_compute(encoder, @build_dispatch_bundle) { |pass| pass.dispatch_workgroups(1, 1, 1) }
          encode_compute(encoder, @scan0_bundle) { |pass| pass.dispatch_workgroups_indirect(resources.prefix_dispatch_args_buffer, offset: 0) }
          encode_compute(encoder, @scan1_bundle) { |pass| pass.dispatch_workgroups_indirect(resources.prefix_dispatch_args_buffer, offset: 16) }
          encode_compute(encoder, @scan2_bundle) { |pass| pass.dispatch_workgroups_indirect(resources.prefix_dispatch_args_buffer, offset: 32) }
          encode_compute(encoder, @add1_bundle) { |pass| pass.dispatch_workgroups_indirect(resources.prefix_dispatch_args_buffer, offset: 48) }
          encode_compute(encoder, @add0_bundle) { |pass| pass.dispatch_workgroups_indirect(resources.prefix_dispatch_args_buffer, offset: 64) }
          encode_compute(encoder, @build_total_bundle) { |pass| pass.dispatch_workgroups(1, 1, 1) }
          return
        end

        return unless encoder.respond_to?(:dispatch_compute)

        STEPS.each do |step|
          if step[0] == :dispatch
            encoder.dispatch_compute(step[1], step[2], step[3], step[4])
          elsif encoder.respond_to?(:dispatch_compute_indirect)
            encoder.dispatch_compute_indirect(step[1], resources.prefix_dispatch_args_buffer, step[2])
          end
        end
      end

      private

      def create_pipelines
        @prefix_params0 = static_buffer("Prefix Params Level 0", BinaryPack.u32(0), usage: [:uniform])
        @prefix_params1 = static_buffer("Prefix Params Level 1", BinaryPack.u32(1), usage: [:uniform])
        @prefix_params2 = static_buffer("Prefix Params Level 2", BinaryPack.u32(2), usage: [:uniform])
        @pair_count_params = static_buffer("Pair Count Params", BinaryPack.u32(@resources.max_pairs), usage: [:uniform])

        @build_dispatch_bundle = compute_bundle(
          "build_dispatch_args.compute.wgsl",
          layout_entries: [buffer_layout(0), buffer_layout(1), buffer_layout(2)],
          bind_entries: [
            buffer_entry(0, @resources.visible_count_buffer),
            buffer_entry(1, @resources.prefix_dispatch_args_buffer),
            buffer_entry(2, @resources.prefix_counts_buffer)
          ]
        )

        @scan0_bundle = scan_bundle(@prefix_params0, @resources.tiles_touched_buffer, @resources.offsets_buffer, @resources.block_sums0_buffer)
        @scan1_bundle = scan_bundle(@prefix_params1, @resources.block_sums0_buffer, @resources.block_offsets0_buffer, @resources.block_sums1_buffer)
        @scan2_bundle = scan_bundle(@prefix_params2, @resources.block_sums1_buffer, @resources.block_offsets1_buffer, @resources.block_sums2_buffer)
        @add1_bundle = add_bundle(@prefix_params1, @resources.block_offsets0_buffer, @resources.block_offsets1_buffer)
        @add0_bundle = add_bundle(@prefix_params0, @resources.offsets_buffer, @resources.block_offsets0_buffer)

        @build_total_bundle = compute_bundle(
          "build_total_pairs.compute.wgsl",
          layout_entries: [
            buffer_layout(0, type: :read_only_storage),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2),
            buffer_layout(3, type: :uniform)
          ],
          bind_entries: [
            buffer_entry(0, @resources.prefix_counts_buffer),
            buffer_entry(1, @resources.block_sums1_buffer),
            buffer_entry(2, @resources.total_pairs_buffer),
            buffer_entry(3, @pair_count_params)
          ]
        )
      end

      def scan_bundle(params, input_values, output_values, block_sums)
        compute_bundle(
          "scan_exclusive_level.compute.wgsl",
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2, type: :read_only_storage),
            buffer_layout(3),
            buffer_layout(4)
          ],
          bind_entries: [
            buffer_entry(0, params),
            buffer_entry(1, @resources.prefix_counts_buffer),
            buffer_entry(2, input_values),
            buffer_entry(3, output_values),
            buffer_entry(4, block_sums)
          ]
        )
      end

      def add_bundle(params, values, block_offsets)
        compute_bundle(
          "add_block_offsets.compute.wgsl",
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2),
            buffer_layout(3, type: :read_only_storage)
          ],
          bind_entries: [
            buffer_entry(0, params),
            buffer_entry(1, @resources.prefix_counts_buffer),
            buffer_entry(2, values),
            buffer_entry(3, block_offsets)
          ]
        )
      end
    end
  end
end
