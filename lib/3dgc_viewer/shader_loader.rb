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
      @module_cache = {}
      @released = false
    end

    def source(name)
      ensure_not_released!
      path = shader_path(name)
      raise ShaderError, "shader not found: #{path}" unless File.file?(path)

      return File.binread(path) unless @cache_sources

      @source_cache[name] ||= File.binread(path)
    end

    def reload!
      ensure_not_released!
      release_modules
      @source_cache.clear
      self
    end

    def module(name)
      ensure_not_released!
      @module_cache[name] ||= create_module(name)
    end

    def release
      return if @released

      release_modules
      @source_cache.clear
      @released = true
    end

    private

    def create_module(name)
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

    def release_modules
      @module_cache.each_value { |shader_module| shader_module.release if shader_module.respond_to?(:release) }
      @module_cache.clear
    end

    def ensure_not_released!
      return unless @released

      raise ShaderError, "shader loader was used after release"
    end

    def shader_path(name)
      path = File.expand_path(name, @shader_dir)
      return path if path == @shader_dir || path.start_with?("#{@shader_dir}#{File::SEPARATOR}")

      raise ShaderError, "shader path escapes shader directory: #{name}"
    end
  end
end
