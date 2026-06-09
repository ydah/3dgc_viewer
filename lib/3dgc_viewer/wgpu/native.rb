# frozen_string_literal: true

require "ffi"
require_relative "../errors"
require_relative "../library_locator"

module ThreeDgcViewer
  module WGPU
    module Native
      extend FFI::Library

      class << self
        attr_reader :loaded

        def load!
          return if @loaded

          ffi_lib LibraryLocator.wgpu_native_path
          attach_core_functions
          @loaded = true
        rescue LoadError, FFI::NotFoundError => e
          raise WgpuError, "failed to load wgpu-native (set WGPU_NATIVE_LIB if needed): #{e.message}"
        end

        private

        def attach_core_functions
          attach_function :wgpuCreateInstance, [:pointer], :pointer
          attach_function :wgpuInstanceCreateSurface, [:pointer, :pointer], :pointer
          attach_function :wgpuInstanceRequestAdapter, [:pointer, :pointer, :pointer], :void
          attach_function :wgpuAdapterRequestDevice, [:pointer, :pointer, :pointer], :void
          attach_function :wgpuDeviceGetQueue, [:pointer], :pointer

          attach_function :wgpuSurfaceGetCapabilities, [:pointer, :pointer, :pointer], :void
          attach_function :wgpuSurfaceCapabilitiesFreeMembers, [:pointer], :void
          attach_function :wgpuSurfaceConfigure, [:pointer, :pointer], :void
          attach_function :wgpuSurfaceGetCurrentTexture, [:pointer, :pointer], :void
          attach_function :wgpuSurfacePresent, [:pointer], :void

          attach_function :wgpuDeviceCreateBuffer, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateTexture, [:pointer, :pointer], :pointer
          attach_function :wgpuTextureCreateView, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateSampler, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateShaderModule, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateBindGroupLayout, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateBindGroup, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreatePipelineLayout, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateComputePipeline, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateRenderPipeline, [:pointer, :pointer], :pointer
          attach_function :wgpuDeviceCreateCommandEncoder, [:pointer, :pointer], :pointer

          attach_function :wgpuQueueWriteBuffer, [:pointer, :pointer, :uint64, :pointer, :size_t], :void
          attach_function :wgpuQueueSubmit, [:pointer, :size_t, :pointer], :void

          attach_function :wgpuCommandEncoderBeginComputePass, [:pointer, :pointer], :pointer
          attach_function :wgpuComputePassEncoderSetPipeline, [:pointer, :pointer], :void
          attach_function :wgpuComputePassEncoderSetBindGroup, [:pointer, :uint32, :pointer, :size_t, :pointer], :void
          attach_function :wgpuComputePassEncoderDispatchWorkgroups, [:pointer, :uint32, :uint32, :uint32], :void
          attach_function :wgpuComputePassEncoderDispatchWorkgroupsIndirect, [:pointer, :pointer, :uint64], :void
          attach_function :wgpuComputePassEncoderEnd, [:pointer], :void

          attach_function :wgpuCommandEncoderBeginRenderPass, [:pointer, :pointer], :pointer
          attach_function :wgpuRenderPassEncoderSetPipeline, [:pointer, :pointer], :void
          attach_function :wgpuRenderPassEncoderSetBindGroup, [:pointer, :uint32, :pointer, :size_t, :pointer], :void
          attach_function :wgpuRenderPassEncoderSetVertexBuffer, [:pointer, :uint32, :pointer, :uint64, :uint64], :void
          attach_function :wgpuRenderPassEncoderDraw, [:pointer, :uint32, :uint32, :uint32, :uint32], :void
          attach_function :wgpuRenderPassEncoderEnd, [:pointer], :void
          attach_function :wgpuCommandEncoderFinish, [:pointer, :pointer], :pointer

          attach_release_functions
        end

        def attach_release_functions
          %i[
            Buffer Texture TextureView Sampler ShaderModule BindGroupLayout BindGroup
            PipelineLayout ComputePipeline RenderPipeline CommandEncoder CommandBuffer
            Queue Device Adapter Surface Instance
          ].each do |name|
            attach_function :"wgpu#{name}Release", [:pointer], :void
          end
        end
      end
    end
  end
end
