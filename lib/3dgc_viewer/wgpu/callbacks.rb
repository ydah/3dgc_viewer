# frozen_string_literal: true

module ThreeDgcViewer
  module WGPU
    module Callbacks
      @store = {}

      module_function

      def store(key, callback)
        @store[key] = callback
      end

      def fetch(key)
        @store[key]
      end
    end
  end
end
