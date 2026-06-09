# frozen_string_literal: true

module ThreeDgcViewer
  module BinaryPack
    module_function

    def f32(*values)
      values.flatten.pack("e*").b
    end

    def u32(*values)
      values.flatten.pack("L<*").b
    end

    def i32(*values)
      values.flatten.pack("l<*").b
    end

    def concat(*chunks)
      chunks.join.b
    end
  end
end
