# frozen_string_literal: true

require "tempfile"

module ThreeDgcViewer
  module AtomicFile
    module_function

    def write(path, bytes, binmode: false)
      tmp_path = nil
      Tempfile.create([".#{File.basename(path)}.", ".tmp"], File.dirname(path), binmode: binmode) do |file|
        tmp_path = file.path
        file.write(bytes)
        file.flush
        file.close
        File.rename(tmp_path, path)
        tmp_path = nil
      end
    ensure
      File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
    end
  end
end
