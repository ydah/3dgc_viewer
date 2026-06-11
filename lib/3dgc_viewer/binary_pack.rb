# frozen_string_literal: true

module ThreeDgcViewer
  module BinaryPack
    module_function

    def f32(*values)
      pack_values(values, "e*")
    end

    def u32(*values)
      pack_values(values, "L<*")
    end

    def i32(*values)
      pack_values(values, "l<*")
    end

    def concat(*chunks)
      buffer = String.new(capacity: chunks.sum(&:bytesize), encoding: Encoding::BINARY)
      chunks.each { |chunk| buffer << chunk }
      buffer
    end

    def pack_values(values, directive)
      if values.none? { |value| value.is_a?(Array) }
        return values.pack(directive).b
      end

      if values.length == 1 && values.first.is_a?(Array)
        array = values.first
        return array.pack(directive).b if array.none? { |value| value.is_a?(Array) }
      end

      values.flatten.pack(directive).b
    end
  end
end
