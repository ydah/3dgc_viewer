# frozen_string_literal: true

require_relative "base_pass"
require_relative "../binary_pack"

module ThreeDgcViewer
  module Passes
    class AxisPass < BasePass
      SHADER_NAME = "axis.wgsl"
      AXIS_LENGTH = 10_000.0

      VERTICES = [
        [-AXIS_LENGTH, 0.0, 0.0, 1.0, 0.1, 0.1],
        [AXIS_LENGTH, 0.0, 0.0, 1.0, 0.1, 0.1],
        [0.0, -AXIS_LENGTH, 0.0, 0.1, 1.0, 0.1],
        [0.0, AXIS_LENGTH, 0.0, 0.1, 1.0, 0.1],
        [0.0, 0.0, -AXIS_LENGTH, 0.1, 0.3, 1.0],
        [0.0, 0.0, AXIS_LENGTH, 0.1, 0.3, 1.0]
      ].freeze

      def self.vertex_bytes
        BinaryPack.f32(VERTICES)
      end

      def initialize(scene_uniform_buffer: nil, surface_format: nil, **kwargs)
        super(**kwargs)
        @scene_uniform_buffer = scene_uniform_buffer
        @surface_format = surface_format
        create_pipeline if gpu_enabled? && @scene_uniform_buffer && @surface_format
      end

      def recreate_bind_group(resources: @resources, scene_uniform_buffer: @scene_uniform_buffer, **_kwargs)
        @resources = resources
        @scene_uniform_buffer = scene_uniform_buffer
        release
        @released = false
        @gpu_objects = []
        @shader_modules = {}
        create_pipeline if gpu_enabled? && @scene_uniform_buffer && @surface_format
      end

      def encode(encoder, surface_texture_view: nil, resources: @resources)
        super(encoder, resources: resources)
        if @pipeline && surface_texture_view
          pass = encoder.begin_render_pass(
            color_attachments: [{
              view: surface_texture_view,
              load_op: :load,
              store_op: :store
            }]
          )
          pass.set_pipeline(@pipeline)
          pass.set_bind_group(0, @bind_group)
          pass.set_vertex_buffer(0, @vertex_buffer)
          pass.draw(6, instance_count: 1, first_vertex: 0, first_instance: 0)
          pass.end_pass
          return
        end

        encoder.draw_axis(SHADER_NAME, 6) if encoder.respond_to?(:draw_axis)
      end

      private

      def create_pipeline
        @vertex_buffer = static_buffer("Axis Vertex Buffer", self.class.vertex_bytes, usage: [:vertex])
        @bind_group_layout = keep(@device.create_bind_group_layout(
          label: "Axis BGL",
          entries: [buffer_layout(0, type: :uniform, visibility: :vertex)]
        ))
        @bind_group = keep(@device.create_bind_group(
          label: "Axis Bind Group",
          layout: @bind_group_layout,
          entries: [buffer_entry(0, @scene_uniform_buffer)]
        ))
        @pipeline = render_pipeline(
          label: "Axis",
          shader_name: SHADER_NAME,
          bind_group_layouts: [@bind_group_layout],
          vertex: {
            entry_point: "vs_main",
            buffers: [{
              array_stride: 24,
              step_mode: :vertex,
              attributes: [
                {format: :float32x3, offset: 0, shader_location: 0},
                {format: :float32x3, offset: 12, shader_location: 1}
              ]
            }]
          },
          primitive: {topology: :line_list},
          fragment: {
            entry_point: "fs_main",
            targets: [{
              format: @surface_format,
              write_mask: :all,
              blend: {
                color: {operation: :add, src_factor: :src_alpha, dst_factor: :one_minus_src_alpha},
                alpha: {operation: :add, src_factor: :one, dst_factor: :one_minus_src_alpha}
              }
            }]
          }
        )
      end
    end
  end
end
