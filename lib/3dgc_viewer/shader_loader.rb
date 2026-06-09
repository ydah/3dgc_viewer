# frozen_string_literal: true

require_relative "errors"
require_relative "library_locator"

module ThreeDgcViewer
  class ShaderLoader
    def initialize(device = nil, shader_dir: LibraryLocator.shader_dir)
      @device = device
      @shader_dir = shader_dir
    end

    def source(name)
      path = File.join(@shader_dir, name)
      raise ShaderError, "shader not found: #{path}" unless File.file?(path)

      File.binread(path)
    end

    def module(name)
      source = source(name)
      if @device.respond_to?(:create_shader_module)
        return @device.create_shader_module(label: name, code: source)
      end

      if @device.respond_to?(:create_shader_module_wgsl)
        return @device.create_shader_module_wgsl(label: name, source: source)
      end

      raise ShaderError, "device does not support WGSL shader module creation"
    end
  end
end
