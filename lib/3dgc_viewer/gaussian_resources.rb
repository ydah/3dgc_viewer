# frozen_string_literal: true

require_relative "gaussian"
require_relative "scene"

module ThreeDgcViewer
  class GaussianResources
    BufferSpec = Struct.new(:name, :size, :usage, keyword_init: true)

    attr_reader :gaussian_set, :gaussian_count, :count1, :max_pairs,
                :max_blocks0, :max_blocks1, :max_blocks2,
                :radix_num_workgroups, :radix_histogram_len,
                :render_width, :render_height,
                :tiles_width, :tiles_height, :tile_count,
                :buffer_specs, :buffers

    def self.next_pair_capacity(required_pairs, current_max_pairs)
      required = [required_pairs.to_i, current_max_pairs.to_i + 1, 1].max
      capacity = 1
      capacity <<= 1 while capacity < required
      capacity
    end

    def initialize(device: nil, queue: nil, gaussian_set:, render_width: Scene::SCREEN_WIDTH, render_height: Scene::SCREEN_HEIGHT, max_pairs: nil)
      @device = device
      @queue = queue
      @gaussian_set = gaussian_set
      @gaussian_count = gaussian_set.items.length
      @count1 = [@gaussian_count, 1].max
      @max_pairs = [max_pairs || (@count1 * 32), 1].max
      @max_blocks0 = ceil_div(@count1, 256)
      @max_blocks1 = ceil_div(@max_blocks0, 256)
      @max_blocks2 = ceil_div(@max_blocks1, 256)
      @radix_num_workgroups = Gaussian::MAX_RADIX_WORKGROUPS
      @radix_histogram_len = @radix_num_workgroups * Gaussian::RADIX_SORT_BINS
      @render_width = positive_int(render_width)
      @render_height = positive_int(render_height)
      @tiles_width = ceil_div(@render_width, Scene::TILE_W)
      @tiles_height = ceil_div(@render_height, Scene::TILE_H)
      @tile_count = @tiles_width * @tiles_height
      @buffer_specs = build_buffer_specs
      @buffers = {}
      create_buffers if @device
    end

    def release
      @buffers.each_value { |buffer| buffer.release if buffer.respond_to?(:release) }
      @buffers.clear
    end

    def respond_to_missing?(name, include_private = false)
      buffer_specs.any? { |spec| spec.name == name } || super
    end

    def method_missing(name, *args, &block)
      return @buffers[name] if args.empty? && @buffers.key?(name)

      super
    end

    def gaussian_bytes
      packed = Gaussian.pack_set(@gaussian_set)
      return packed unless packed.empty?

      "\0".b * Gaussian.item_size(@gaussian_set.kind)
    end

    private

    def ceil_div(value, divisor)
      (value + divisor - 1) / divisor
    end

    def positive_int(value)
      [value.to_i, 1].max
    end

    def build_buffer_specs
      gaussian_size = Gaussian.item_size(@gaussian_set.kind) * @count1

      [
        BufferSpec.new(name: :gaussian_buffer, size: gaussian_size, usage: %i[storage]),
        BufferSpec.new(name: :preprocess_output_buffer, size: 64 * @count1, usage: %i[storage copy_src]),
        BufferSpec.new(name: :tiles_touched_buffer, size: 4 * @count1, usage: %i[storage copy_src]),
        BufferSpec.new(name: :visible_count_buffer, size: 4, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :prefix_dispatch_args_buffer, size: 16 * Gaussian::PREFIX_DISPATCH_ARGS_COUNT, usage: %i[storage indirect copy_dst copy_src]),
        BufferSpec.new(name: :prefix_counts_buffer, size: 16, usage: %i[storage copy_dst copy_src]),
        BufferSpec.new(name: :offsets_buffer, size: 4 * @count1, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :block_sums0_buffer, size: 4 * @max_blocks0, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :block_offsets0_buffer, size: 4 * @max_blocks0, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :block_sums1_buffer, size: 4 * @max_blocks1, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :block_offsets1_buffer, size: 4 * @max_blocks1, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :block_sums2_buffer, size: 4 * @max_blocks2, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :pair_keys_buffer, size: 8 * @max_pairs, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :pair_values_buffer, size: 4 * @max_pairs, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :pair_keys_tmp_buffer, size: 8 * @max_pairs, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :pair_values_tmp_buffer, size: 4 * @max_pairs, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :radix_histograms_buffer, size: 4 * @radix_histogram_len, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :total_pairs_buffer, size: 16, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :radix_params_buffer, size: 16 * Gaussian::RADIX_SORT_PASSES, usage: %i[storage copy_src copy_dst]),
        BufferSpec.new(name: :radix_dispatch_args_buffer, size: 16, usage: %i[storage indirect copy_src copy_dst]),
        BufferSpec.new(name: :tile_range_dispatch_args_buffer, size: 16, usage: %i[storage indirect copy_src copy_dst]),
        BufferSpec.new(name: :tile_ranges_buffer, size: 8 * @tile_count, usage: %i[storage copy_src copy_dst])
      ]
    end

    def create_buffers
      @buffer_specs.each do |spec|
        data = spec.name == :gaussian_buffer ? gaussian_bytes : nil
        @buffers[spec.name] = create_buffer(spec, data)
      end
    end

    def create_buffer(spec, data)
      if data && @device.respond_to?(:create_buffer_with_data)
        return @device.create_buffer_with_data(label: spec.name.to_s, data: data, usage: spec.usage)
      end

      buffer = @device.create_buffer(label: spec.name.to_s, size: spec.size, usage: spec.usage, mapped_at_creation: false)
      if data && @queue&.respond_to?(:write_buffer)
        @queue.write_buffer(buffer, 0, data)
      elsif data && buffer.respond_to?(:write)
        buffer.write(data)
      end
      buffer
    end
  end
end
