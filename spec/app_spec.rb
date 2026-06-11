# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tempfile"

RSpec.describe ThreeDgcViewer::App do
  def required_3d
    %w[
      x y z opacity scale_0 scale_1 scale_2
      rot_0 rot_1 rot_2 rot_3 f_dc_0 f_dc_1 f_dc_2
    ]
  end

  def build_ply_file
    file = Tempfile.new(["scene", ".ply"])
    header = +"ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
    required_3d.each { |name| header << "property float #{name}\n" }
    header << "end_header\n"
    row = [1.0, 2.0, 3.0, 0.4, 0.1, 0.2, 0.3, 1.0, 0.0, 0.0, 0.0, 0.7, 0.8, 0.9]
    file.binmode
    file.write(header.b)
    file.write(row.pack("e*"))
    file.close
    file
  end

  it "parses internal render size options" do
    options = described_class.parse_options(%w[
      --render-width 321
      --render-height 181
      --render-size-window
    ])

    expect(options.render_width).to eq(321)
    expect(options.render_height).to eq(181)
    expect(options.render_size_window).to eq(true)
  end

  it "derives render size from render scale" do
    options = described_class.parse_options(%w[
      --width 640
      --height 360
      --render-scale 0.5
    ])

    expect(options.render_width).to eq(320)
    expect(options.render_height).to eq(180)
  end

  it "parses camera and playback options" do
    screenshot = Tempfile.new(["frame", ".ppm"])
    preset = Tempfile.new(["camera", ".json"])
    preset.write(JSON.generate(
      eye: [9.0, 8.0, 7.0],
      target: [6.0, 5.0, 4.0],
      up: [0.0, 1.0, 0.0],
      fov: 55.0,
      znear: 0.3,
      zfar: 300.0
    ))
    preset.close
    screenshot.close
    options = described_class.parse_options(%w[
      --time 0.25
      --time-speed 2.5
      --pause
      --turntable-speed 30
      --power-preference low-power
      --present-mode mailbox
      --background-color #336699cc
      --transparent-background
      --exposure 1.5
      --gamma 2.2
      --brightness 0.1
      --contrast 1.2
      --opacity-threshold 0.01
      --scale-multiplier 0.75
      --quality fast
      --low-vram
      --watch
      --benchmark 3
      --frame-sequence-count 4
      --frame-sequence-step 0.25
    ] + [
      "--camera-preset", preset.path,
      "--screenshot", screenshot.path,
      "--frame-sequence", File.join(File.dirname(screenshot.path), "frame_%04d.pam")
    ])

    expect(options.eye).to eq([9.0, 8.0, 7.0])
    expect(options.target).to eq([6.0, 5.0, 4.0])
    expect(options.up).to eq([0.0, 1.0, 0.0])
    expect(options.fov).to eq(55.0)
    expect(options.znear).to eq(0.3)
    expect(options.zfar).to eq(300.0)
    expect(options.time).to eq(0.25)
    expect(options.time_speed).to eq(2.5)
    expect(options.pause).to eq(true)
    expect(options.turntable_speed).to eq(30.0)
    expect(options.power_preference).to eq(:low_power)
    expect(options.present_mode).to eq(:mailbox)
    expect(options.background_color).to eq([0x33 / 255.0, 0x66 / 255.0, 0x99 / 255.0, 0.0])
    expect(options.exposure).to eq(1.5)
    expect(options.gamma).to eq(2.2)
    expect(options.brightness).to eq(0.1)
    expect(options.contrast).to eq(1.2)
    expect(options.opacity_threshold).to eq(0.01)
    expect(options.scale_multiplier).to eq(0.75)
    expect(options.quality).to eq(:fast)
    expect(options.low_vram).to eq(true)
    expect(options.watch).to eq(true)
    expect(options.benchmark).to eq(3)
    expect(options.screenshot).to eq(screenshot.path)
    expect(options.frame_sequence).to end_with("frame_%04d.pam")
    expect(options.frame_sequence_count).to eq(4)
    expect(options.frame_sequence_step).to eq(0.25)
  ensure
    screenshot&.unlink
    preset&.unlink
  end

  it "saves the initial camera preset and exits" do
    preset = Tempfile.new(["camera", ".json"])
    preset.close

    result = described_class.run(["--save-camera-preset", preset.path, "--eye", "1,2,3", "--target", "4,5,6"])
    data = JSON.parse(File.read(preset.path))

    expect(result).to eq(0)
    expect(data.fetch("eye")).to eq([1.0, 2.0, 3.0])
    expect(data.fetch("target")).to eq([4.0, 5.0, 6.0])
  ensure
    preset&.unlink
  end

  it "loads a named camera bookmark during option parsing" do
    bookmarks = Tempfile.new(["bookmarks", ".json"])
    bookmarks.write(JSON.generate(
      "front" => {
        "eye" => [9.0, 8.0, 7.0],
        "target" => [6.0, 5.0, 4.0],
        "up" => [0.0, 1.0, 0.0],
        "fov" => 35.0
      }
    ))
    bookmarks.close

    options = described_class.parse_options(["--camera-bookmarks", bookmarks.path, "--camera-bookmark", "front"])

    expect(options.eye).to eq([9.0, 8.0, 7.0])
    expect(options.target).to eq([6.0, 5.0, 4.0])
    expect(options.fov).to eq(35.0)
  ensure
    bookmarks&.unlink
  end

  it "saves and prints camera bookmarks" do
    bookmarks = Tempfile.new(["bookmarks", ".json"])
    bookmarks.close

    save_result = described_class.run([
      "--camera-bookmarks", bookmarks.path,
      "--save-camera-bookmark", "front",
      "--eye", "1,2,3"
    ])
    output = capture_stdout do
      described_class.run(["--camera-bookmarks", bookmarks.path, "--print-camera-bookmarks", "--json"])
    end

    expect(save_result).to eq(0)
    expect(JSON.parse(output)).to eq(["front"])
  ensure
    bookmarks&.unlink
  end

  it "rejects invalid log level" do
    expect { described_class.parse_options(%w[--log-level trace]) }
      .to raise_error(OptionParser::InvalidArgument, /log-level/)
  end

  it "rejects invalid dimensions" do
    expect { described_class.parse_options(%w[--width 0]) }
      .to raise_error(OptionParser::InvalidArgument, /width/)
  end

  it "rejects invalid camera options" do
    expect { described_class.parse_options(%w[--fov 180]) }
      .to raise_error(OptionParser::InvalidArgument, /fov/)
    expect { described_class.parse_options(%w[--up 0,0,0]) }
      .to raise_error(OptionParser::InvalidArgument, /up/)
  end

  it "rejects invalid tone mapping options" do
    expect { described_class.parse_options(%w[--background-color 2,0,0]) }
      .to raise_error(OptionParser::InvalidArgument, /background-color/)
    expect { described_class.parse_options(%w[--exposure 0]) }
      .to raise_error(OptionParser::InvalidArgument, /exposure/)
    expect { described_class.parse_options(%w[--gamma 0]) }
      .to raise_error(OptionParser::InvalidArgument, /gamma/)
    expect { described_class.parse_options(%w[--brightness NaN]) }
      .to raise_error(OptionParser::InvalidArgument, /brightness/)
    expect { described_class.parse_options(%w[--contrast 0]) }
      .to raise_error(OptionParser::InvalidArgument, /contrast/)
    expect { described_class.parse_options(%w[--opacity-threshold 1.1]) }
      .to raise_error(OptionParser::InvalidArgument, /opacity-threshold/)
    expect { described_class.parse_options(%w[--scale-multiplier 0]) }
      .to raise_error(OptionParser::InvalidArgument, /scale-multiplier/)
  end

  it "rejects invalid turntable speed" do
    expect { described_class.parse_options(%w[--turntable-speed NaN]) }
      .to raise_error(OptionParser::InvalidArgument, /turntable-speed/)
  end

  it "rejects invalid quality presets" do
    expect { described_class.parse_options(%w[--quality ultra]) }
      .to raise_error(OptionParser::InvalidArgument, /quality/)
  end

  it "rejects invalid batch render options" do
    expect { described_class.parse_options(%w[--benchmark 0]) }
      .to raise_error(OptionParser::InvalidArgument, /benchmark/)
    expect { described_class.parse_options(%w[--screenshot frame.png]) }
      .to raise_error(OptionParser::InvalidArgument, /screenshot/)
    expect { described_class.parse_options(%w[--window-only --benchmark 1]) }
      .to raise_error(OptionParser::InvalidArgument, /window-only/)
  end

  it "rejects invalid frame sequence options" do
    expect { described_class.parse_options(%w[--frame-sequence frame.pam]) }
      .to raise_error(OptionParser::InvalidArgument, /frame-sequence/)
    expect { described_class.parse_options(%w[--frame-sequence-count 2]) }
      .to raise_error(OptionParser::InvalidArgument, /frame-sequence-count/)
  end

  it "accepts PAM screenshots for RGBA output" do
    screenshot = Tempfile.new(["frame", ".pam"])
    screenshot.close

    options = described_class.parse_options(["--screenshot", screenshot.path])

    expect(options.screenshot).to eq(screenshot.path)
  ensure
    screenshot&.unlink
  end

  it "checks startup file paths during option parsing" do
    expect { described_class.parse_options(%w[--file /missing/model.ply]) }
      .to raise_error(OptionParser::InvalidArgument, /does not exist/)
  end

  it "returns a distinct exit code for PLY runtime errors" do
    expect(described_class.run(%w[--validate-ply])).to eq(3)
  end

  it "prints validate-only results as JSON" do
    file = build_ply_file

    output = capture_stdout { described_class.run(["--file", file.path, "--validate-ply", "--json"]) }
    data = JSON.parse(output)

    expect(data.fetch("kind")).to eq("gaussian3d")
    expect(data.fetch("gaussians")).to eq(1)
  ensure
    file&.unlink
  end

  it "prints scene information without initializing the window" do
    file = build_ply_file
    result = nil

    expect do
      result = described_class.run(["--file", file.path, "--print-scene-info"])
    end.to output(/kind: gaussian3d\n/).to_stdout

    expect(result).to eq(0)
  ensure
    file&.unlink
  end

  it "prints scene information as JSON" do
    file = build_ply_file

    output = capture_stdout { described_class.run(["--file", file.path, "--print-scene-info", "--json"]) }

    data = JSON.parse(output)
    expect(data.fetch("kind")).to eq("gaussian3d")
    expect(data.fetch("gaussians")).to eq(1)
  ensure
    file&.unlink
  end

  it "prints native library locator information without initializing the window" do
    result = nil

    expect do
      result = described_class.run(["--print-gpu-info"])
    end.to output(/platform:/).to_stdout

    expect(result).to eq(0)
  end

  it "prints native library locator information as JSON" do
    output = capture_stdout { described_class.run(%w[--print-gpu-info --json]) }
    data = JSON.parse(output)

    expect(data).to include("platform", "wgpu_native", "glfw", "surface_shim")
  end

  it "prints controls without initializing the window" do
    output = capture_stdout { described_class.run(%w[--print-controls --json]) }
    data = JSON.parse(output)

    expect(data).to include(include("keys" => "F", "action" => "Fit view to scene"))
  end

  it "prints recent files from the configured history store" do
    history = Tempfile.new(["recent", ".json"])
    history.write(JSON.generate([File.expand_path("scene.ply")]))
    history.close

    output = capture_stdout do
      described_class.run(["--print-recent-files", "--recent-files", history.path, "--json"])
    end

    expect(JSON.parse(output)).to eq([File.expand_path("scene.ply")])
  ensure
    history&.unlink
  end

  it "can write logs as JSON lines" do
    stderr = nil
    capture_stdout do
      stderr = capture_stderr { described_class.run(%w[--print-gpu-info --log-json]) }
    end
    first_log = JSON.parse(stderr.lines.first)

    expect(first_log).to include("time", "level", "progname", "message")
    expect(first_log.fetch("level")).to eq("info")
  end

  def capture_stdout
    original = $stdout
    buffer = StringIO.new
    $stdout = buffer
    yield
    buffer.string
  ensure
    $stdout = original
  end

  def capture_stderr
    original = $stderr
    buffer = StringIO.new
    $stderr = buffer
    yield
    buffer.string
  ensure
    $stderr = original
  end
end
