# frozen_string_literal: true

require_relative "base_pass"
require_relative "../binary_pack"

module ThreeDgcViewer
  module Passes
    class RadixSortPass < BasePass
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
        if @build_bundle
          encode_compute(encoder, @build_bundle) { |pass| pass.dispatch_workgroups(1, 1, 1) }
          Gaussian::RADIX_SORT_PASSES.times do |i|
            encode_compute(encoder, @hist_bundles[i]) { |pass| pass.dispatch_workgroups_indirect(resources.radix_dispatch_args_buffer, offset: 0) }
            encode_compute(encoder, @scatter_bundles[i]) { |pass| pass.dispatch_workgroups_indirect(resources.radix_dispatch_args_buffer, offset: 0) }
          end
          return
        end

        return unless encoder.respond_to?(:dispatch_compute)

        encoder.dispatch_compute("build_radix_args.compute.wgsl", 1, 1, 1)
        Gaussian::RADIX_SORT_PASSES.times do
          if encoder.respond_to?(:dispatch_compute_indirect)
            encoder.dispatch_compute_indirect("radix_hist.compute.wgsl", resources.radix_dispatch_args_buffer, 0)
            encoder.dispatch_compute_indirect("radix_scatter.compute.wgsl", resources.radix_dispatch_args_buffer, 0)
          end
        end
      end

      private

      def create_pipelines
        @pass_index_buffers = Gaussian::RADIX_SORT_PASSES.times.map do |i|
          static_buffer("Radix Pass Index #{i}", BinaryPack.u32(i), usage: [:uniform])
        end

        @build_bundle = compute_bundle(
          "build_radix_args.compute.wgsl",
          layout_entries: [buffer_layout(0, type: :read_only_storage), buffer_layout(1), buffer_layout(2), buffer_layout(3)],
          bind_entries: [
            buffer_entry(0, @resources.total_pairs_buffer),
            buffer_entry(1, @resources.radix_params_buffer),
            buffer_entry(2, @resources.radix_dispatch_args_buffer),
            buffer_entry(3, @resources.tile_range_dispatch_args_buffer)
          ]
        )

        @hist_bundles = []
        @scatter_bundles = []
        Gaussian::RADIX_SORT_PASSES.times do |i|
          keys_in, keys_out, values_in, values_out = ping_pong_buffers(i)
          @hist_bundles << hist_bundle(i, keys_in)
          @scatter_bundles << scatter_bundle(i, keys_in, keys_out, values_in, values_out)
        end
      end

      def ping_pong_buffers(pass_index)
        if pass_index.even?
          [@resources.pair_keys_buffer, @resources.pair_keys_tmp_buffer, @resources.pair_values_buffer, @resources.pair_values_tmp_buffer]
        else
          [@resources.pair_keys_tmp_buffer, @resources.pair_keys_buffer, @resources.pair_values_tmp_buffer, @resources.pair_values_buffer]
        end
      end

      def hist_bundle(pass_index, keys_in)
        compute_bundle(
          "radix_hist.compute.wgsl",
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2, type: :read_only_storage),
            buffer_layout(3)
          ],
          bind_entries: [
            buffer_entry(0, @pass_index_buffers[pass_index]),
            buffer_entry(1, @resources.radix_params_buffer),
            buffer_entry(2, keys_in),
            buffer_entry(3, @resources.radix_histograms_buffer)
          ]
        )
      end

      def scatter_bundle(pass_index, keys_in, keys_out, values_in, values_out)
        compute_bundle(
          "radix_scatter.compute.wgsl",
          layout_entries: [
            buffer_layout(0, type: :uniform),
            buffer_layout(1, type: :read_only_storage),
            buffer_layout(2, type: :read_only_storage),
            buffer_layout(3),
            buffer_layout(4, type: :read_only_storage),
            buffer_layout(5),
            buffer_layout(6, type: :read_only_storage)
          ],
          bind_entries: [
            buffer_entry(0, @pass_index_buffers[pass_index]),
            buffer_entry(1, @resources.radix_params_buffer),
            buffer_entry(2, keys_in),
            buffer_entry(3, keys_out),
            buffer_entry(4, values_in),
            buffer_entry(5, values_out),
            buffer_entry(6, @resources.radix_histograms_buffer)
          ]
        )
      end
    end
  end
end
