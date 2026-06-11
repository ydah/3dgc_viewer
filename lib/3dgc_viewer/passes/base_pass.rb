# frozen_string_literal: true

require_relative "../errors"

module ThreeDgcViewer
  module Passes
    class BasePass
      attr_reader :device, :resources, :shader_loader

      def initialize(device: nil, resources:, shader_loader:, **_kwargs)
        @device = device
        @resources = resources
        @shader_loader = shader_loader
        @gpu_objects = []
        @shader_modules = {}
        @released = false
      end

      def recreate_bind_group(resources: @resources, **_kwargs)
        @resources = resources
        @released = false
      end

      def encode(_encoder, resources: @resources)
        ensure_not_released!
        @resources = resources
      end

      def release
        return if @released

        @gpu_objects.reverse_each { |object| object.release if object.respond_to?(:release) }
        @gpu_objects.clear
        @released = true
      end

      private

      def gpu_enabled?
        @device && @device.respond_to?(:create_bind_group_layout)
      end

      def ensure_not_released!
        return unless @released

        raise ResourceError, "#{self.class.name} was used after release"
      end

      def shader_module(name)
        @shader_modules[name] ||= keep(@shader_loader.module(name))
      end

      def keep(object)
        @gpu_objects << object if object.respond_to?(:release)
        object
      end

      def compute_bundle(shader_name, layout_entries:, bind_entries:)
        return {} unless gpu_enabled?

        layout = keep(@device.create_bind_group_layout(label: "#{shader_name} BGL", entries: layout_entries))
        pipeline_layout = keep(@device.create_pipeline_layout(label: "#{shader_name} Pipeline Layout", bind_group_layouts: [layout]))
        pipeline = keep(@device.create_compute_pipeline(
          label: "#{shader_name} Pipeline",
          layout: pipeline_layout,
          compute: {module: shader_module(shader_name), entry_point: "main"}
        ))
        bind_group = keep(@device.create_bind_group(label: "#{shader_name} Bind Group", layout: layout, entries: bind_entries))
        {layout: layout, pipeline_layout: pipeline_layout, pipeline: pipeline, bind_group: bind_group}
      end

      def render_pipeline(label:, shader_name:, bind_group_layouts:, vertex:, fragment:, primitive: {}, depth_stencil: nil)
        return nil unless gpu_enabled?

        pipeline_layout = keep(@device.create_pipeline_layout(label: "#{label} Pipeline Layout", bind_group_layouts: bind_group_layouts))
        keep(@device.create_render_pipeline(
          label: "#{label} Pipeline",
          layout: pipeline_layout,
          vertex: vertex.merge(module: shader_module(shader_name)),
          primitive: primitive,
          depth_stencil: depth_stencil,
          fragment: fragment.merge(module: shader_module(shader_name))
        ))
      end

      def buffer_layout(binding, type: :storage, visibility: :compute)
        {binding: binding, visibility: visibility, buffer: {type: type}}
      end

      def texture_layout(binding, sample_type: :float, visibility: :fragment)
        {binding: binding, visibility: visibility, texture: {sample_type: sample_type, view_dimension: :d2}}
      end

      def sampler_layout(binding, type: :filtering, visibility: :fragment)
        {binding: binding, visibility: visibility, sampler: {type: type}}
      end

      def storage_texture_layout(binding, access: :write_only, format: :rgba8_unorm, visibility: :compute)
        {binding: binding, visibility: visibility, storage_texture: {access: access, format: format, view_dimension: :d2}}
      end

      def buffer_entry(binding, buffer)
        {binding: binding, buffer: buffer, offset: 0, size: buffer.size}
      end

      def texture_entry(binding, texture_view)
        {binding: binding, texture_view: texture_view}
      end

      def sampler_entry(binding, sampler)
        {binding: binding, sampler: sampler}
      end

      def static_buffer(label, data, usage: [:uniform])
        if @device.respond_to?(:create_buffer_with_data)
          keep(@device.create_buffer_with_data(label: label, data: data, usage: usage))
        else
          buffer = keep(@device.create_buffer(label: label, size: data.bytesize, usage: usage, mapped_at_creation: false))
          buffer.write(data) if buffer.respond_to?(:write)
          buffer
        end
      end

      def encode_compute(encoder, bundle)
        return unless bundle[:pipeline] && bundle[:bind_group]

        pass = encoder.begin_compute_pass
        pass.set_pipeline(bundle[:pipeline])
        pass.set_bind_group(0, bundle[:bind_group])
        yield pass
        pass.end_pass
      end
    end
  end
end
