require_relative "lib/3dgc_viewer/version"

Gem::Specification.new do |spec|
  spec.name = "3dgc_viewer"
  spec.version = ThreeDgcViewer::VERSION
  spec.authors = ["Yudai Takada"]
  spec.summary = "Ruby native desktop Gaussian Splatting viewer using wgpu-native."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb"] +
    Dir["bin/*"] +
    Dir["shaders/*.wgsl"] +
    Dir["ext/**/*.{rb,h,c,m}"] +
    ["LICENSE"]
  spec.bindir = "bin"
  spec.executables = ["3dgc_viewer"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/3dgc_viewer_native/extconf.rb"]

  spec.add_dependency "ffi", "~> 1.17"
  spec.add_dependency "logger", "~> 1.7"
  spec.add_dependency "wgpu", "~> 1.1"
end
