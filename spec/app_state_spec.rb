# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"
require "tempfile"

RSpec.describe ThreeDgcViewer::AppState do
  FakeWindow = Struct.new(:width, :height, :title) do
    def framebuffer_size
      [width, height]
    end
  end

  def build_ply_file(extension = ".ply")
    file = Tempfile.new(["scene", extension])
    required = %w[
      x y z opacity scale_0 scale_1 scale_2
      rot_0 rot_1 rot_2 rot_3 f_dc_0 f_dc_1 f_dc_2
    ]
    header = +"ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
    required.each { |name| header << "property float #{name}\n" }
    header << "end_header\n"
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    file.binmode
    file.write(header.b)
    file.write(row.pack("e*"))
    file.close
    file
  end

  def quiet_logger
    Logger.new(StringIO.new)
  end

  def string_logger
    output = StringIO.new
    [Logger.new(output), output]
  end

  it "fits the camera when replacing gaussians with scene bounds" do
    state = described_class.new(FakeWindow.new(1280, 720))
    bounds = ThreeDgcViewer::Gaussian::Bounds.new(
      min: [10.0, 20.0, 30.0],
      max: [12.0, 22.0, 32.0]
    )
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(
      kind: :gaussian3d,
      count: 0,
      statistics: ThreeDgcViewer::Gaussian::Statistics.new(
        count: 0,
        bounds: bounds,
        invalid_count: 0
      )
    )

    state.replace_gaussians(set)

    expect(state.camera.target).to eq([11.0, 21.0, 31.0])
    expect(state.camera.zfar).to be > state.camera.znear
  end

  it "uses configured initial camera and time controls" do
    camera = ThreeDgcViewer::Camera.default(width: 1280, height: 720)
    camera.eye = [1.0, 2.0, 3.0]
    camera.target = [4.0, 5.0, 6.0]
    camera.fovy = 60.0
    state = described_class.new(
      FakeWindow.new(1280, 720),
      initial_camera: camera,
      initial_time: 0.25,
      time_speed: 2.0,
      time_range: [0.2, 0.8],
      time_paused: true,
      turntable_speed: 30.0,
      background_color: [0.1, 0.2, 0.3, 1.0],
      exposure: 1.5,
      gamma: 2.2,
      brightness: 0.1,
      contrast: 1.2,
      opacity_threshold: 0.01,
      scale_multiplier: 0.75
    )

    expect(state.camera.eye).to eq([1.0, 2.0, 3.0])
    expect(state.camera.target).to eq([4.0, 5.0, 6.0])
    expect(state.camera.fovy).to eq(60.0)
    expect(state.scene_uniform.time).to eq(0.25)
    expect(state.time_speed).to eq(2.0)
    expect(state.time_range).to eq([0.2, 0.8])
    expect(state.time_paused).to eq(true)
    expect(state.turntable_speed).to eq(30.0)
    expect(state.turntable_enabled).to eq(true)
    expect(state.scene_uniform.background_color).to eq([0.1, 0.2, 0.3, 1.0])
    expect(state.scene_uniform.exposure).to eq(1.5)
    expect(state.scene_uniform.gamma).to eq(2.2)
    expect(state.scene_uniform.brightness).to eq(0.1)
    expect(state.scene_uniform.contrast).to eq(1.2)
    expect(state.scene_uniform.opacity_threshold).to eq(0.01)
    expect(state.scene_uniform.scale_multiplier).to eq(0.75)
  end

  it "can set sequence capture time directly" do
    state = described_class.new(FakeWindow.new(1280, 720), initial_time: 0.25, time_range: [0.2, 0.6])

    state.set_time(0.75)

    expect(state.scene_uniform.time).to be_within(1e-9).of(0.35)
  end

  it "reports missing GPU adapters as WgpuError" do
    instance = Class.new do
      def request_adapter(**_kwargs)
        nil
      end
    end.new
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger, power_preference: :low_power)
    state.instance_variable_set(:@instance, instance)
    state.instance_variable_set(:@surface, Object.new)
    allow(ThreeDgcViewer::LibraryLocator).to receive(:platform).and_return("test-platform")

    expect { state.send(:request_adapter!) }
      .to raise_error(ThreeDgcViewer::WgpuError, /no suitable GPU adapter.*low_power.*test-platform/)
  end

  it "reports device request failures as WgpuError" do
    adapter = Class.new do
      def request_device
        nil
      end

      def info
        {name: "Test Adapter"}
      end
    end.new
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger)
    state.instance_variable_set(:@adapter, adapter)

    expect { state.send(:request_device!) }
      .to raise_error(ThreeDgcViewer::WgpuError, /failed to request GPU device.*Test Adapter/)
  end

  it "warns when the requested present mode is unavailable" do
    logger, output = string_logger
    state = described_class.new(FakeWindow.new(1280, 720), logger: logger, present_mode: :mailbox)

    mode = state.send(:choose_present_mode, [:fifo])

    expect(mode).to eq(:fifo)
    expect(output.string).to include("requested present mode :mailbox is unavailable")
  end

  it "handles fit reset and axis toggle shortcuts" do
    state = described_class.new(FakeWindow.new(1280, 720))
    bounds = ThreeDgcViewer::Gaussian::Bounds.new(
      min: [10.0, 20.0, 30.0],
      max: [12.0, 22.0, 32.0]
    )
    set = ThreeDgcViewer::Gaussian::GaussianSet.new(
      kind: :gaussian3d,
      count: 0,
      statistics: ThreeDgcViewer::Gaussian::Statistics.new(count: 0, bounds: bounds, invalid_count: 0)
    )
    state.replace_gaussians(set)

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_R, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.camera.target).to eq([0.0, 0.0, 0.0])

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_F, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.camera.target).to eq([11.0, 21.0, 31.0])

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_X, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.show_axis).to eq(false)
  end

  it "toggles turntable animation from the keyboard shortcut" do
    state = described_class.new(FakeWindow.new(1280, 720), turntable_speed: 10.0)

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_T, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.turntable_enabled).to eq(false)

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_T, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.turntable_enabled).to eq(true)
  end

  it "toggles playback pause from the keyboard shortcut" do
    state = described_class.new(FakeWindow.new(1280, 720), time_paused: false)

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_SPACE, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.time_paused).to eq(true)

    state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_SPACE, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    expect(state.time_paused).to eq(false)
  end

  it "reloads shader passes from the keyboard shortcut in shader dev mode" do
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger, shader_dev: true)
    state.instance_variable_set(:@device, Object.new)

    expect do
      state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_H, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    end.not_to raise_error
  end

  it "handles mouse orbit pan and scroll events" do
    state = described_class.new(FakeWindow.new(1280, 720))
    initial_eye = state.camera.eye
    initial_target = state.camera.target

    state.handle_mouse_button(ThreeDgcViewer::Window::GLFW::MOUSE_BUTTON_LEFT, ThreeDgcViewer::Window::GLFW::GLFW_PRESS, 10.0, 10.0)
    state.handle_cursor(40.0, 20.0)
    state.handle_mouse_button(ThreeDgcViewer::Window::GLFW::MOUSE_BUTTON_LEFT, ThreeDgcViewer::Window::GLFW::GLFW_RELEASE, 40.0, 20.0)
    expect(state.camera.eye).not_to eq(initial_eye)

    state.handle_mouse_button(ThreeDgcViewer::Window::GLFW::MOUSE_BUTTON_RIGHT, ThreeDgcViewer::Window::GLFW::GLFW_PRESS, 20.0, 20.0)
    state.handle_cursor(25.0, 50.0)
    state.handle_mouse_button(ThreeDgcViewer::Window::GLFW::MOUSE_BUTTON_RIGHT, ThreeDgcViewer::Window::GLFW::GLFW_RELEASE, 25.0, 50.0)
    expect(state.camera.target).not_to eq(initial_target)

    eye_after_pan = state.camera.eye
    state.handle_scroll(0.0, 1.0)
    expect(state.camera.eye).not_to eq(eye_after_pan)
  end

  it "summarizes render texture pixels for batch verification" do
    state = described_class.new(FakeWindow.new(1280, 720), render_width: 3, render_height: 1)
    rgba = [1, 2, 3, 4, 0, 0, 0, 5, 255, 255, 255, 6].pack("C*")
    state.define_singleton_method(:render_texture_rgba_bytes) { rgba }

    stats = state.render_texture_statistics

    expect(stats).to include(
      width: 3,
      height: 1,
      pixels: 3,
      nonzero_rgb_pixels: 2,
      rgb_sum: 771,
      alpha_sum: 15
    )
    expect(stats[:luminance_histogram].values_at(0, 15)).to eq([2, 1])
    expect(stats[:checksum]).to be_a(Integer)
  end

  it "rejects truncated render texture readbacks" do
    state = described_class.new(FakeWindow.new(1280, 720), render_width: 2, render_height: 1)
    state.define_singleton_method(:render_texture_rgba_bytes) { "\0\0\0\0".b }

    expect { state.render_texture_statistics }
      .to raise_error(ThreeDgcViewer::WgpuError, /readback size/)
  end

  it "reuses gaussian resources when render resize keeps the same tile grid" do
    pass_class = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def recreate_bind_group(**kwargs)
        @calls << kwargs
      end
    end
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger, render_width: 320, render_height: 180)
    resources = state.resources
    tile_pass = pass_class.new
    screen_pass = pass_class.new
    state.instance_variable_set(:@device, Object.new)
    state.instance_variable_set(:@tile_render_pass, tile_pass)
    state.instance_variable_set(:@screen_blit_pass, screen_pass)
    state.define_singleton_method(:recreate_render_texture) do
      @render_texture_view = :new_view
      @render_texture_sampler = :new_sampler
    end
    state.define_singleton_method(:replace_gaussians) { |_gaussian_set, **_kwargs| raise "should not replace resources" }

    state.send(:resize_render_target, 319, 179)

    expect(state.resources).to equal(resources)
    expect(resources.render_width).to eq(319)
    expect(resources.render_height).to eq(179)
    expect(tile_pass.calls.first).to include(resources: resources, render_texture_view: :new_view)
    expect(screen_pass.calls.first).to include(resources: resources, render_texture_view: :new_view, render_texture_sampler: :new_sampler)
  end

  it "skips GPU rendering while the framebuffer is occluded" do
    state = described_class.new(FakeWindow.new(0, 0), logger: quiet_logger)
    state.instance_variable_set(:@is_surface_configured, true)
    state.define_singleton_method(:render_gpu_frame) { raise "should not render" }

    expect { state.render }.not_to raise_error
  end

  it "updates the window title after loading a file" do
    file = build_ply_file(".notply")
    window = FakeWindow.new(1280, 720)
    state = described_class.new(window, logger: quiet_logger)

    state.handle_drop(file.path)

    expect(window.title).to include(File.basename(file.path))
    expect(window.title).to include("1 gaussians")
  ensure
    file&.unlink
  end

  it "tracks recent files and handles multiple drops explicitly" do
    first = build_ply_file(".ply")
    second = build_ply_file(".ply")
    window = FakeWindow.new(1280, 720)
    state = described_class.new(window, logger: quiet_logger)

    state.handle_drops([first.path, second.path])

    expect(state.recent_files.first).to eq(File.expand_path(first.path))
    expect(window.title).to include(File.basename(first.path))
  ensure
    first&.unlink
    second&.unlink
  end

  it "persists recent files after a successful load" do
    file = build_ply_file(".ply")
    history = Tempfile.new(["recent", ".json"])
    history_path = history.path
    history.close
    history.unlink
    store = ThreeDgcViewer::RecentFiles.new(path: history_path)
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger, recent_files_store: store)

    state.handle_drop(file.path)

    expect(store.load.first).to eq(File.expand_path(file.path))
  ensure
    file&.unlink
    File.delete(history_path) if history_path && File.exist?(history_path)
  end

  it "reloads the current scene from the keyboard shortcut" do
    file = build_ply_file(".ply")
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger)
    state.handle_drop(file.path)

    expect do
      state.handle_key(ThreeDgcViewer::Window::Keymap::KEY_L, ThreeDgcViewer::Window::GLFW::GLFW_PRESS)
    end.not_to change { state.resources.gaussian_count }
  ensure
    file&.unlink
  end

  it "keeps the current scene when a dropped file fails to load" do
    valid = build_ply_file(".ply")
    invalid = Tempfile.new(["invalid", ".ply"])
    invalid.write("not a ply")
    invalid.close
    window = FakeWindow.new(1280, 720)
    state = described_class.new(window, logger: quiet_logger)
    state.handle_drop(valid.path)
    previous_title = window.title

    state.handle_drop(invalid.path)

    expect(state.resources.gaussian_count).to eq(1)
    expect(state.recent_files.first).to eq(File.expand_path(valid.path))
    expect(window.title).to eq(previous_title)
  ensure
    valid&.unlink
    invalid&.unlink
  end

  it "does not repeatedly reload the same failed watched file change" do
    file = build_ply_file(".ply")
    logger, output = string_logger
    state = described_class.new(FakeWindow.new(1280, 720), logger: logger, watch_files: true)
    state.handle_drop(file.path)
    File.binwrite(file.path, "not a ply")
    changed_at = Time.now + 10
    File.utime(changed_at, changed_at, file.path)
    state.instance_variable_set(:@scene_mtime, Time.at(0))

    state.update
    state.update

    expect(state.resources.gaussian_count).to eq(1)
    expect(state.instance_variable_get(:@scene_mtime)).to be > Time.at(0)
    expect(output.string.scan("PLY load failed").length).to eq(1)
  ensure
    file&.unlink
  end

  it "handles missing dropped files without raising" do
    missing = Tempfile.new(["missing", ".ply"])
    path = missing.path
    missing.close
    missing.unlink
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger)

    expect { state.handle_drop(path) }.not_to raise_error
  end

  it "releases owned GPU objects at most once" do
    releasable_class = Class.new do
      attr_reader :release_count

      def initialize
        @release_count = 0
      end

      def release
        @release_count += 1
      end
    end
    object = releasable_class.new
    shader_loader = releasable_class.new
    state = described_class.new(FakeWindow.new(1280, 720), logger: quiet_logger)
    state.instance_variable_set(:@scene_uniform_buffer, object)
    state.instance_variable_set(:@shader_loader, shader_loader)

    state.release
    state.release

    expect(object.release_count).to eq(1)
    expect(shader_loader.release_count).to eq(1)
  end
end
