# frozen_string_literal: true

require "json"

module ThreeDgcViewer
  module CameraPreset
    VECTOR_FIELDS = %i[eye target up].freeze
    FLOAT_FIELDS = %i[fov znear zfar].freeze

    module_function

    def load_file(path)
      data = JSON.parse(File.read(path))
      raise ArgumentError, "camera preset must be a JSON object" unless data.is_a?(Hash)

      load_hash(data)
    rescue JSON::ParserError => e
      raise ArgumentError, e.message
    end

    def load_hash(data)
      preset = {}
      VECTOR_FIELDS.each do |field|
        value = data[field.to_s] || data[field]
        preset[field] = validate_vec3(value, field) if value
      end
      FLOAT_FIELDS.each do |field|
        value = data[field.to_s] || data[field]
        preset[field] = validate_float(value, field) if value
      end
      preset
    end

    def apply_to_options(options, preset)
      options.eye = preset[:eye] if preset.key?(:eye)
      options.target = preset[:target] if preset.key?(:target)
      options.up = preset[:up] if preset.key?(:up)
      options.fov = preset[:fov] if preset.key?(:fov)
      options.znear = preset[:znear] if preset.key?(:znear)
      options.zfar = preset[:zfar] if preset.key?(:zfar)
      options
    end

    def hash_from_camera(camera)
      {
        eye: camera.eye,
        target: camera.target,
        up: camera.up,
        fov: camera.fovy,
        znear: camera.znear,
        zfar: camera.zfar
      }
    end

    def write_file(path, camera)
      File.write(path, "#{JSON.pretty_generate(hash_from_camera(camera))}\n")
    end

    def validate_vec3(value, field)
      vector = Array(value)
      raise ArgumentError, "#{field} must have 3 numbers" unless vector.length == 3

      vector = vector.map { |component| Float(component, exception: false) }
      raise ArgumentError, "#{field} must contain only finite numbers" unless vector.all? { |component| component&.finite? }

      vector
    end
    private_class_method :validate_vec3

    def validate_float(value, field)
      number = Float(value, exception: false)
      raise ArgumentError, "#{field} must be finite" unless number&.finite?

      number
    end
    private_class_method :validate_float
  end
end
