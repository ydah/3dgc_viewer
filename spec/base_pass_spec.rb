# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Passes::BasePass do
  it "releases tracked GPU objects at most once" do
    objects = 2.times.map do
      Class.new do
        attr_reader :release_count

        def initialize
          @release_count = 0
        end

        def release
          @release_count += 1
        end
      end.new
    end
    pass = described_class.new(resources: nil, shader_loader: nil)
    pass.instance_variable_set(:@gpu_objects, objects.dup)

    pass.release
    pass.release

    expect(objects.map(&:release_count)).to eq([1, 1])
  end

  it "rejects encode after release until recreated" do
    pass = described_class.new(resources: nil, shader_loader: nil)

    pass.release

    expect { pass.encode(nil) }
      .to raise_error(ThreeDgcViewer::ResourceError, /used after release/)

    pass.recreate_bind_group(resources: nil)
    expect { pass.encode(nil) }.not_to raise_error
  end

  it "does not own shader modules returned by the shared shader loader" do
    shader_module = Class.new do
      attr_reader :release_count

      def initialize
        @release_count = 0
      end

      def release
        @release_count += 1
      end
    end.new
    loader = Class.new do
      define_method(:initialize) { |shader_module| @shader_module = shader_module }
      define_method(:module) { |_name| @shader_module }
    end.new(shader_module)
    pass = described_class.new(resources: nil, shader_loader: loader)

    expect(pass.send(:shader_module, "shared.wgsl")).to equal(shader_module)
    pass.release

    expect(shader_module.release_count).to eq(0)
  end

  it "reports shader name and entry point when compute pipeline creation fails" do
    device = Class.new do
      def create_bind_group_layout(**_kwargs)
        :layout
      end

      def create_pipeline_layout(**_kwargs)
        :pipeline_layout
      end

      def create_compute_pipeline(**_kwargs)
        raise "compile failed at line 12"
      end
    end.new
    loader = Class.new do
      def module(_name)
        :shader_module
      end
    end.new
    pass = described_class.new(device: device, resources: nil, shader_loader: loader)

    expect do
      pass.send(:compute_bundle, "bad.compute.wgsl", layout_entries: [], bind_entries: [])
    end.to raise_error(
      ThreeDgcViewer::ShaderError,
      /compute pipeline shader=bad\.compute\.wgsl entry_point=main: compile failed at line 12/
    )
  end

  it "reports shader name and entry points when render pipeline creation fails" do
    device = Class.new do
      def create_bind_group_layout(**_kwargs)
        :layout
      end

      def create_pipeline_layout(**_kwargs)
        :pipeline_layout
      end

      def create_render_pipeline(**_kwargs)
        raise "fragment output mismatch"
      end
    end.new
    loader = Class.new do
      def module(_name)
        :shader_module
      end
    end.new
    pass = described_class.new(device: device, resources: nil, shader_loader: loader)

    expect do
      pass.send(
        :render_pipeline,
        label: "Screen Blit",
        shader_name: "screen_blit.render.wgsl",
        bind_group_layouts: [],
        vertex: {entry_point: "vs_main"},
        fragment: {entry_point: "fs_main"}
      )
    end.to raise_error(
      ThreeDgcViewer::ShaderError,
      /render pipeline label=Screen Blit shader=screen_blit\.render\.wgsl vertex_entry=vs_main fragment_entry=fs_main: fragment output mismatch/
    )
  end
end
