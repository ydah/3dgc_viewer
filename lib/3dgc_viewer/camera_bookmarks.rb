# frozen_string_literal: true

require "json"
require_relative "camera_preset"

module ThreeDgcViewer
  module CameraBookmarks
    module_function

    def load_file(path)
      data = JSON.parse(File.read(path))
      raise ArgumentError, "camera bookmarks must be a JSON object" unless data.is_a?(Hash)

      data.each_with_object({}) do |(raw_name, preset_data), bookmarks|
        name = normalize_name(raw_name)
        raise ArgumentError, "camera bookmark #{raw_name.inspect} must be a JSON object" unless preset_data.is_a?(Hash)

        bookmarks[name] = CameraPreset.load_hash(preset_data)
      end
    rescue JSON::ParserError => e
      raise ArgumentError, e.message
    end

    def fetch_file(path, name)
      bookmarks = load_file(path)
      bookmark = bookmarks[normalize_name(name)]
      raise ArgumentError, "camera bookmark not found: #{name}" unless bookmark

      bookmark
    end

    def names_file(path)
      load_file(path).keys
    end

    def write_file(path, name, camera)
      name = normalize_name(name)

      data = File.file?(path) && File.size(path).positive? ? load_raw_file(path) : {}
      data[name] = stringify_keys(CameraPreset.hash_from_camera(camera))
      CameraPreset.write_json_file(path, data)
    end

    def load_raw_file(path)
      data = JSON.parse(File.read(path))
      raise ArgumentError, "camera bookmarks must be a JSON object" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise ArgumentError, e.message
    end
    private_class_method :load_raw_file

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
    private_class_method :stringify_keys

    def normalize_name(name)
      normalized = name.to_s.strip
      raise ArgumentError, "camera bookmark name must not be empty" if normalized.empty?

      normalized
    end
    private_class_method :normalize_name
  end
end
