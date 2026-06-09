# frozen_string_literal: true

require "ffi"
require_relative "../errors"
require_relative "../library_locator"

module ThreeDgcViewer
  module WGPU
    module SurfaceShim
      extend FFI::Library

      class << self
        attr_reader :loaded

        def load!
          return if @loaded

          ffi_lib LibraryLocator.surface_shim_path
          attach_function :rbwgv_create_surface, [:pointer, :pointer], :pointer
          @loaded = true
        rescue LoadError, FFI::NotFoundError => e
          raise WgpuError, "failed to load surface shim (build ext/3dgc_viewer_native first): #{e.message}"
        end
      end
    end
  end
end
