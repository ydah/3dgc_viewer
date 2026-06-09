# frozen_string_literal: true

module ThreeDgcViewer
  module WGPU
    module Constants
      # Keep these values synchronized with the vendored webgpu.h/wgpu.h release.
      BUFFER_USAGE_MAP_READ = 0x00000001
      BUFFER_USAGE_MAP_WRITE = 0x00000002
      BUFFER_USAGE_COPY_SRC = 0x00000004
      BUFFER_USAGE_COPY_DST = 0x00000008
      BUFFER_USAGE_INDEX = 0x00000010
      BUFFER_USAGE_VERTEX = 0x00000020
      BUFFER_USAGE_UNIFORM = 0x00000040
      BUFFER_USAGE_STORAGE = 0x00000080
      BUFFER_USAGE_INDIRECT = 0x00000100
      BUFFER_USAGE_QUERY_RESOLVE = 0x00000200

      TEXTURE_USAGE_COPY_SRC = 0x00000001
      TEXTURE_USAGE_COPY_DST = 0x00000002
      TEXTURE_USAGE_TEXTURE_BINDING = 0x00000004
      TEXTURE_USAGE_STORAGE_BINDING = 0x00000008
      TEXTURE_USAGE_RENDER_ATTACHMENT = 0x00000010

      RGBA8_UNORM = 18
      BGRA8_UNORM = 23
      DEPTH32_FLOAT = 42

      PRESENT_MODE_FIFO = 2
      COMPOSITE_ALPHA_AUTO = 0

      LOAD_OP_LOAD = 1
      LOAD_OP_CLEAR = 2
      STORE_OP_STORE = 1

      SHADER_STAGE_VERTEX = 0x1
      SHADER_STAGE_FRAGMENT = 0x2
      SHADER_STAGE_COMPUTE = 0x4

      module_function

      def buffer_usage(*flags)
        flags.flatten.reduce(0) do |mask, flag|
          mask | const_get("BUFFER_USAGE_#{flag.to_s.upcase}")
        end
      end
    end
  end
end
