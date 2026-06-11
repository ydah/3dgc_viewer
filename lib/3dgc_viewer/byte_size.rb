# frozen_string_literal: true

module ThreeDgcViewer
  module ByteSize
    UNITS = %w[B KiB MiB GiB TiB].freeze

    module_function

    def format(bytes)
      value = bytes.to_f
      unit = UNITS.first
      UNITS.each do |candidate|
        unit = candidate
        break if value < 1024.0 || candidate == UNITS.last

        value /= 1024.0
      end
      "#{value.round(1)} #{unit}"
    end
  end
end
