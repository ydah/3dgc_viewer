# frozen_string_literal: true

require_relative "base_pass"

module ThreeDgcViewer
  module Passes
    class TileRenderPass < BasePass
      SHADER_NAME = "tile_render.compute.wgsl"

      def initialize(scene_uniform_buffer: nil, render_texture_view: nil, **kwargs)
        super(**kwargs)
        @scene_uniform_buffer = scene_uniform_buffer
        @render_texture_view = render_texture_view
        create_pipeline if gpu_enabled? && @scene_uniform_buffer && @render_texture_view
      end

      def recreate_bind_group(resources: @resources, scene_uniform_buffer: @scene_uniform_buffer, render_texture_view: @render_texture_view, **_kwargs)
        @resources = resources
        @scene_uniform_buffer = scene_uniform_buffer
        @render_texture_view = render_texture_view
        release
        @released = false
        @gpu_objects = []
        @shader_modules = {}
        create_pipeline if gpu_enabled? && @scene_uniform_buffer && @render_texture_view
      end

      def encode(encoder, resources: @resources)
        super
        if @bundle
          encode_compute(encoder, @bundle) { |pass| pass.dispatch_workgroups(resources.tiles_width, resources.tiles_height, 1) }
          return
        end

        return unless encoder.respond_to?(:dispatch_compute)

        encoder.dispatch_compute(SHADER_NAME, resources.tiles_width, resources.tiles_height, 1)
      end

      private

      def create_pipeline
        @bundle = compute_bundle(
          SHADER_NAME,
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2, type: :read_only_storage),
            buffer_layout(3, type: :read_only_storage),
            storage_texture_layout(4, access: :write_only, format: :rgba8_unorm),
            buffer_layout(5, type: :read_only_storage)
          ],
          bind_entries: [
            buffer_entry(0, @scene_uniform_buffer),
            buffer_entry(1, @resources.preprocess_output_buffer),
            buffer_entry(2, @resources.tile_ranges_buffer),
            buffer_entry(3, @resources.pair_values_buffer),
            texture_entry(4, @render_texture_view),
            buffer_entry(5, @resources.total_pairs_buffer)
          ]
        )
      end
    end
  end
end
