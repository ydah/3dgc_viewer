# frozen_string_literal: true

require_relative "base_pass"

module ThreeDgcViewer
  module Passes
    class ScreenBlitPass < BasePass
      SHADER_NAME = "screen_blit.wgsl"

      def initialize(render_texture_view: nil, render_texture_sampler: nil, surface_format: nil, depth_format: nil, **kwargs)
        super(**kwargs)
        @render_texture_view = render_texture_view
        @render_texture_sampler = render_texture_sampler
        @surface_format = surface_format
        @depth_format = depth_format
        create_pipeline if gpu_enabled? && @render_texture_view && @render_texture_sampler && @surface_format
      end

      def recreate_bind_group(resources: @resources, render_texture_view: @render_texture_view, render_texture_sampler: @render_texture_sampler, **_kwargs)
        @resources = resources
        @render_texture_view = render_texture_view
        @render_texture_sampler = render_texture_sampler
        release
        @released = false
        @gpu_objects = []
        @shader_modules = {}
        create_pipeline if gpu_enabled? && @render_texture_view && @render_texture_sampler && @surface_format
      end

      def encode(encoder, surface_texture_view: nil, depth_texture_view: nil, resources: @resources)
        super(encoder, resources: resources)
        if @pipeline && surface_texture_view
          pass = encoder.begin_render_pass(
            color_attachments: [{
              view: surface_texture_view,
              load_op: :clear,
              store_op: :store,
              clear_value: {r: 0.0, g: 0.0, b: 0.0, a: 1.0}
            }],
            depth_stencil_attachment: depth_texture_view ? {
              view: depth_texture_view,
              depth_load_op: :clear,
              depth_store_op: :store,
              depth_clear_value: 1.0
            } : nil
          )
          pass.set_pipeline(@pipeline)
          pass.set_bind_group(0, @bind_group)
          pass.draw(3, instance_count: 1, first_vertex: 0, first_instance: 0)
          pass.end_pass
          return
        end

        encoder.draw_fullscreen_triangle(SHADER_NAME) if encoder.respond_to?(:draw_fullscreen_triangle)
      end

      private

      def create_pipeline
        @bind_group_layout = keep(@device.create_bind_group_layout(
          label: "Screen Blit BGL",
          entries: [
            texture_layout(0, sample_type: :float, visibility: :fragment),
            sampler_layout(1, type: :filtering, visibility: :fragment)
          ]
        ))
        @bind_group = keep(@device.create_bind_group(
          label: "Screen Blit Bind Group",
          layout: @bind_group_layout,
          entries: [
            texture_entry(0, @render_texture_view),
            sampler_entry(1, @render_texture_sampler)
          ]
        ))
        @pipeline = render_pipeline(
          label: "Screen Blit",
          shader_name: SHADER_NAME,
          bind_group_layouts: [@bind_group_layout],
          vertex: {entry_point: "vs_main", buffers: []},
          primitive: {topology: :triangle_list},
          depth_stencil: @depth_format ? {format: @depth_format, depth_write_enabled: true, depth_compare: :less} : nil,
          fragment: {entry_point: "fs_main", targets: [{format: @surface_format, write_mask: :all}]}
        )
      end
    end
  end
end
