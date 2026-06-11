# frozen_string_literal: true

module ThreeDgcViewer
  class Error < StandardError; end
  class WgpuError < Error; end
  class PlyError < Error; end
  class ShaderError < Error; end
  class ResourceError < Error; end
  class WindowError < Error; end
end
