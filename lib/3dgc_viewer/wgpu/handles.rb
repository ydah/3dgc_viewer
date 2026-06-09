# frozen_string_literal: true

require "ffi"
require_relative "../errors"

module ThreeDgcViewer
  module WGPU
    class Handle
      attr_reader :ptr, :label

      def initialize(ptr, release: nil, label: nil)
        raise WgpuError, "null handle: #{label}" if ptr.nil? || ptr.null?

        @ptr = ptr
        @release = release
        @label = label
        @released = false
      end

      def release
        return if @released

        @release&.call(@ptr)
        @released = true
      end
    end
  end
end
