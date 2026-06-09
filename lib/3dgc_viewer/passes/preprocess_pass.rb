# frozen_string_literal: true

require_relative "base_pass"

module ThreeDgcViewer
  module Passes
    class PreprocessPass < BasePass
      attr_reader :scene_type, :shader_name

      def initialize(scene_type:, scene_uniform_buffer: nil, **kwargs)
        super(**kwargs)
        @scene_type = scene_type
        @scene_uniform_buffer = scene_uniform_buffer
        @shader_name = scene_type == :gaussian4d ? "preprocess_4d.compute.wgsl" : "preprocess_3d.compute.wgsl"
        create_pipeline if gpu_enabled? && @scene_uniform_buffer
      end

      def recreate_bind_group(resources: @resources, scene_uniform_buffer: @scene_uniform_buffer, **_kwargs)
        @resources = resources
        @scene_uniform_buffer = scene_uniform_buffer
        release
        @released = false
        @gpu_objects = []
        @shader_modules = {}
        create_pipeline if gpu_enabled? && @scene_uniform_buffer
      end

      def encode(encoder, resources: @resources)
        super
        return if resources.gaussian_count.zero?

        if @bundle
          encode_compute(encoder, @bundle) { |pass| pass.dispatch_workgroups(ceil_div(resources.gaussian_count, 256), 1, 1) }
        elsif encoder.respond_to?(:dispatch_compute)
          encoder.dispatch_compute(@shader_name, ceil_div(resources.gaussian_count, 256), 1, 1)
        end
      end

      private

      def create_pipeline
        @bundle = compute_bundle(
          @shader_name,
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2),
            buffer_layout(3),
            buffer_layout(4)
          ],
          bind_entries: [
            buffer_entry(0, @scene_uniform_buffer),
            buffer_entry(1, @resources.gaussian_buffer),
            buffer_entry(2, @resources.preprocess_output_buffer),
            buffer_entry(3, @resources.tiles_touched_buffer),
            buffer_entry(4, @resources.visible_count_buffer)
          ]
        )
      end

      def ceil_div(value, divisor)
        (value + divisor - 1) / divisor
      end
    end
  end
end
