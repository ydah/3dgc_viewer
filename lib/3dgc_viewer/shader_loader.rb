# frozen_string_literal: true

require_relative "errors"
require_relative "library_locator"

module ThreeDgcViewer
  class ShaderLoader
    attr_reader :cache_sources

    def initialize(device = nil, shader_dir: LibraryLocator.shader_dir, cache_sources: true)
      @device = device
      @shader_dir = File.expand_path(shader_dir)
      @cache_sources = cache_sources
      @source_cache = {}
    end

    def source(name)
      path = shader_path(name)
      raise ShaderError, "shader not found: #{path}" unless File.file?(path)

      return File.binread(path) unless @cache_sources

      @source_cache[name] ||= File.binread(path)
    end

    def reload!
      @source_cache.clear
      self
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
    rescue ShaderError
      raise
    rescue StandardError => e
      raise ShaderError, "failed to create shader module #{name}: #{e.message}"
    end

    private

    def shader_path(name)
      path = File.expand_path(name, @shader_dir)
      return path if path == @shader_dir || path.start_with?("#{@shader_dir}#{File::SEPARATOR}")

      raise ShaderError, "shader path escapes shader directory: #{name}"
    end
  end
end
