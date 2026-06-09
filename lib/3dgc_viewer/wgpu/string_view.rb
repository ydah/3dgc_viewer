# frozen_string_literal: true

require "ffi"

module ThreeDgcViewer
  module WGPU
    class StringView < FFI::Struct
      layout :data, :pointer,
             :length, :size_t
    end

    module StringViewHelpers
      module_function

      def string_view(str)
        mem = FFI::MemoryPointer.from_string(str.to_s)
        view = StringView.new
        view[:data] = mem
        view[:length] = str.to_s.bytesize
        [view, mem]
      end
    end
  end
end
