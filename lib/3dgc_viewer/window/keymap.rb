# frozen_string_literal: true

module ThreeDgcViewer
  module Window
    module Keymap
      KEY_SPACE = 32
      KEY_APOSTROPHE = 39
      KEY_COMMA = 44
      KEY_MINUS = 45
      KEY_PERIOD = 46
      KEY_SLASH = 47
      KEY_0 = 48
      KEY_1 = 49
      KEY_2 = 50
      KEY_3 = 51
      KEY_4 = 52
      KEY_5 = 53
      KEY_6 = 54
      KEY_7 = 55
      KEY_8 = 56
      KEY_9 = 57
      KEY_SEMICOLON = 59
      KEY_EQUAL = 61
      KEY_A = 65
      KEY_C = 67
      KEY_D = 68
      KEY_E = 69
      KEY_F = 70
      KEY_Q = 81
      KEY_R = 82
      KEY_S = 83
      KEY_W = 87
      KEY_X = 88
      KEY_Z = 90
      KEY_ESCAPE = 256
      KEY_RIGHT = 262
      KEY_LEFT = 263
      KEY_DOWN = 264
      KEY_UP = 265

      CAMERA_ACTIONS = {
        KEY_A => :yaw_left,
        KEY_LEFT => :yaw_left,
        KEY_D => :yaw_right,
        KEY_RIGHT => :yaw_right,
        KEY_W => :pitch_up,
        KEY_UP => :pitch_up,
        KEY_S => :pitch_down,
        KEY_DOWN => :pitch_down,
        KEY_Q => :zoom_in,
        KEY_E => :zoom_out,
        KEY_Z => :roll_left,
        KEY_C => :roll_right
      }.freeze

      module_function

      def camera_action(key)
        CAMERA_ACTIONS[key.to_i]
      end
    end
  end
end
