# frozen_string_literal: true

require "ffi"
require_relative "../errors"
require_relative "../library_locator"
require_relative "keymap"

module ThreeDgcViewer
  module Window
    class GLFW
      GLFW_CLIENT_API = 0x00022001
      GLFW_VISIBLE = 0x00020004
      GLFW_NO_API = 0
      GLFW_FALSE = 0
      GLFW_TRUE = 1
      GLFW_PRESS = 1
      GLFW_RELEASE = 0
      GLFW_REPEAT = 2

      module Native
        extend FFI::Library

        class << self
          attr_reader :loaded

          def load!
            return if @loaded

            ffi_lib LibraryLocator.glfw_path
            attach_function :glfwInit, [], :int
            attach_function :glfwTerminate, [], :void
            attach_function :glfwWindowHint, [:int, :int], :void
            attach_function :glfwCreateWindow, [:int, :int, :string, :pointer, :pointer], :pointer
            attach_function :glfwDestroyWindow, [:pointer], :void
            attach_function :glfwWindowShouldClose, [:pointer], :int
            attach_function :glfwSetWindowShouldClose, [:pointer, :int], :void
            attach_function :glfwPollEvents, [], :void
            attach_function :glfwWaitEventsTimeout, [:double], :void
            attach_function :glfwGetFramebufferSize, [:pointer, :pointer, :pointer], :void
            attach_function :glfwGetWindowSize, [:pointer, :pointer, :pointer], :void
            attach_function :glfwSetWindowSize, [:pointer, :int, :int], :void
            attach_function :glfwSetFramebufferSizeCallback, [:pointer, :pointer], :pointer
            attach_function :glfwSetKeyCallback, [:pointer, :pointer], :pointer
            attach_function :glfwSetDropCallback, [:pointer, :pointer], :pointer
            attach_function :glfwGetTime, [], :double
            attach_function :glfwSetWindowTitle, [:pointer, :string], :void
            @loaded = true
          rescue LoadError, FFI::NotFoundError => e
            raise WindowError, "failed to load GLFW (set GLFW_LIB if needed): #{e.message}"
          end
        end
      end

      attr_reader :ptr, :width, :height

      def initialize(width:, height:, title:, visible: true)
        Native.load!
        raise WindowError, "glfwInit failed" if Native.glfwInit.zero?

        @owns_glfw = true
        @width = width
        @height = height
        @callbacks = {}

        Native.glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
        Native.glfwWindowHint(GLFW_VISIBLE, visible ? GLFW_TRUE : GLFW_FALSE)
        @ptr = Native.glfwCreateWindow(width, height, title, FFI::Pointer::NULL, FFI::Pointer::NULL)
        raise WindowError, "glfwCreateWindow failed" if @ptr.null?

        install_callbacks
      end

      def should_close?
        Native.glfwWindowShouldClose(@ptr) != 0
      end

      def request_close
        Native.glfwSetWindowShouldClose(@ptr, 1)
      end

      def poll_events
        Native.glfwPollEvents
      end

      def wait_events_timeout(timeout)
        Native.glfwWaitEventsTimeout(timeout.to_f)
      end

      def framebuffer_size
        width_ptr = FFI::MemoryPointer.new(:int)
        height_ptr = FFI::MemoryPointer.new(:int)
        Native.glfwGetFramebufferSize(@ptr, width_ptr, height_ptr)
        [width_ptr.read_int, height_ptr.read_int]
      end

      def set_size(width, height)
        @width = width
        @height = height
        Native.glfwSetWindowSize(@ptr, width, height)
      end

      def title=(title)
        Native.glfwSetWindowTitle(@ptr, title)
      end

      def on_key(&block)
        @on_key = block
      end

      def on_drop(&block)
        @on_drop = block
      end

      def on_resize(&block)
        @on_resize = block
      end

      def destroy
        if @ptr && !@ptr.null?
          Native.glfwDestroyWindow(@ptr)
          @ptr = nil
        end
        Native.glfwTerminate if @owns_glfw
        @owns_glfw = false
      end

      private

      def install_callbacks
        @callbacks[:key] = FFI::Function.new(:void, [:pointer, :int, :int, :int, :int]) do |_window, key, _scancode, action, _mods|
          @on_key&.call(key, action)
        end
        Native.glfwSetKeyCallback(@ptr, @callbacks[:key])

        @callbacks[:drop] = FFI::Function.new(:void, [:pointer, :int, :pointer]) do |_window, count, paths_ptr|
          paths = count.times.map { |i| paths_ptr.get_pointer(i * FFI::Pointer.size).read_string }
          @on_drop&.call(paths)
        end
        Native.glfwSetDropCallback(@ptr, @callbacks[:drop])

        @callbacks[:resize] = FFI::Function.new(:void, [:pointer, :int, :int]) do |_window, width, height|
          @width = width
          @height = height
          @on_resize&.call(width, height)
        end
        Native.glfwSetFramebufferSizeCallback(@ptr, @callbacks[:resize])
      end
    end
  end
end
