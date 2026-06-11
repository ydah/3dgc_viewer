require "rbconfig"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

RUBY = RbConfig.ruby

task :syntax do
  sh(
    RUBY,
    "-Ilib",
    "-e",
    "Dir['lib/**/*.rb'].sort.each { |path| RubyVM::InstructionSequence.compile_file(path) }; " \
      "RubyVM::InstructionSequence.compile_file('bin/3dgc_viewer'); " \
      "puts 'syntax ok'"
  )
end

task :require_check do
  sh(
    RUBY,
    "-Ilib",
    "-e",
    "require '3dgc_viewer'; puts ThreeDgcViewer::VERSION; puts WgpuGsViewer::VERSION"
  )
end

task :cli_help do
  sh(RUBY, "-Ilib", "bin/3dgc_viewer", "--help")
end

namespace :shader do
  task :validate do
    paths = Dir["shaders/*.wgsl"].sort
    raise "no WGSL shaders found" if paths.empty?

    paths.each do |path|
      source = File.read(path)
      raise "empty shader: #{path}" if source.empty?
      raise "shader has no entry point: #{path}" unless source.match?(/@(compute|vertex|fragment)\b/)
    end
    puts "shader validation ok (#{paths.length} files)"
  end
end

namespace :native do
  task :extconf do
    args = ["-C", "ext/3dgc_viewer_native", "extconf.rb"]
    args << "--with-glfw-dir=#{ENV["GLFW_DIR"]}" if ENV["GLFW_DIR"]
    sh(RUBY, *args)
  end

  task build: :extconf do
    sh("make", "-C", "ext/3dgc_viewer_native")
  end
end

task quality: [:syntax, :require_check, "shader:validate", :spec, :cli_help]
task default: :quality
