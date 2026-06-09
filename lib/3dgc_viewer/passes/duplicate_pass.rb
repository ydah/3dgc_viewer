# frozen_string_literal: true

require_relative "base_pass"
require_relative "../binary_pack"

module ThreeDgcViewer
  module Passes
    class DuplicatePass < BasePass
      SHADER_NAME = "duplicate.compute.wgsl"

      def initialize(**kwargs)
        super
        create_pipeline if gpu_enabled?
      end

      def recreate_bind_group(resources: @resources, **_kwargs)
        @resources = resources
        release
        @released = false
        @gpu_objects = []
        @shader_modules = {}
        create_pipeline if gpu_enabled?
      end

      def encode(encoder, resources: @resources)
        super
        if @bundle
          encode_compute(encoder, @bundle) { |pass| pass.dispatch_workgroups_indirect(resources.prefix_dispatch_args_buffer, offset: 0) }
          return
        end

        return unless encoder.respond_to?(:dispatch_compute_indirect)

        encoder.dispatch_compute_indirect(SHADER_NAME, resources.prefix_dispatch_args_buffer, 0)
      end

      private

      def create_pipeline
        @params_buffer = static_buffer(
          "Duplicate Params",
          BinaryPack.u32(@resources.tiles_width, @resources.tiles_height, @resources.max_pairs, 0),
          usage: [:uniform]
        )
        @bundle = compute_bundle(
          SHADER_NAME,
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2, type: :read_only_storage),
            buffer_layout(3),
            buffer_layout(4),
            buffer_layout(5)
          ],
          bind_entries: [
            buffer_entry(0, @params_buffer),
            buffer_entry(1, @resources.preprocess_output_buffer),
            buffer_entry(2, @resources.offsets_buffer),
            buffer_entry(3, @resources.pair_keys_buffer),
            buffer_entry(4, @resources.pair_values_buffer),
            buffer_entry(5, @resources.visible_count_buffer)
          ]
        )
      end
    end
  end
end
