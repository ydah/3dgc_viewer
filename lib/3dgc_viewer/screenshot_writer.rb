# frozen_string_literal: true

module ThreeDgcViewer
  module ScreenshotWriter
    module_function

    def write(path:, width:, height:, rgba_bytes:)
      case File.extname(path).downcase
      when ".ppm"
        write_ppm(path: path, width: width, height: height, rgba_bytes: rgba_bytes)
      when ".pam"
        write_pam(path: path, width: width, height: height, rgba_bytes: rgba_bytes)
      else
        raise ArgumentError, "unsupported screenshot format: #{File.extname(path)}"
      end
    end

    def write_ppm(path:, width:, height:, rgba_bytes:)
      File.binwrite(path, ppm_bytes(width: width, height: height, rgba_bytes: rgba_bytes))
    end

    def write_pam(path:, width:, height:, rgba_bytes:)
      File.binwrite(path, pam_bytes(width: width, height: height, rgba_bytes: rgba_bytes))
    end

    def ppm_bytes(width:, height:, rgba_bytes:)
      width, height, rgba_bytes = validate_rgba(width: width, height: height, rgba_bytes: rgba_bytes)
      header = "P6\n#{width} #{height}\n255\n".b
      header + rgb_bytes(rgba_bytes)
    end

    def pam_bytes(width:, height:, rgba_bytes:)
      width, height, rgba_bytes = validate_rgba(width: width, height: height, rgba_bytes: rgba_bytes)
      header = "P7\nWIDTH #{width}\nHEIGHT #{height}\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n".b
      header + rgba_bytes
    end

    def validate_rgba(width:, height:, rgba_bytes:)
      width = positive_int(width, "width")
      height = positive_int(height, "height")
      rgba_bytes = rgba_bytes.to_s.b
      expected_size = width * height * 4
      unless rgba_bytes.bytesize == expected_size
        raise ArgumentError, "rgba bytes size must be #{expected_size}, got #{rgba_bytes.bytesize}"
      end

      [width, height, rgba_bytes]
    end
    private_class_method :validate_rgba

    def rgb_bytes(rgba_bytes)
      rgb = String.new(capacity: (rgba_bytes.bytesize / 4) * 3, encoding: Encoding::BINARY)
      rgba_bytes.bytes.each_slice(4) do |red, green, blue, _alpha|
        rgb << red << green << blue
      end
      rgb
    end
    private_class_method :rgb_bytes

    def positive_int(value, name)
      integer = value.to_i
      raise ArgumentError, "#{name} must be positive" unless integer.positive?

      integer
    end
    private_class_method :positive_int
  end
end
