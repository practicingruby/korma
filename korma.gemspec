KORMA_VERSION = "1.0.0" 

Gem::Specification.new do |spec|
  spec.name = "korma"
  spec.version = KORMA_VERSION
  spec.platform = Gem::Platform::RUBY
  spec.summary = "A static site generator for bloggers with multiple author support"
  spec.files =  Dir.glob("{bin,lib}/*") + ["korma.gemspec"]
  spec.require_path = "lib"
  spec.bindir = "bin"
  spec.executables << "korma"

  spec.test_files = Dir[ "test/*_test.rb" ]
  spec.has_rdoc = false
  spec.author = "Gregory Brown"
  spec.email = "  gregory.t.brown@gmail.com"
  spec.add_dependency('builder')
  spec.add_dependency('RedCloth')
  spec.homepage = "http://prawn.majesticseacreature.com"
  spec.description = <<END_DESC
  A static site generator for bloggers with multiple author support
END_DESC
end
