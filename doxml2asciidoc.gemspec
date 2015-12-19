# encoding: UTF-8
require File.expand_path '../lib/doxml2asciidoc/identity', __FILE__

Gem::Specification.new do |s|
  s.name = Doxml2AsciiDoc::Identity.name 
  s.version = Doxml2AsciiDoc::Identity.version
  s.authors = ['Vegard Sandengen']
  s.email = ['vegardsandengen@gmail.com']
  s.homepage = 'https://github.com/veeg/doxml2asciidoc'
  s.summary = 'A Doxygen API documentation in XML format to AsciiDoc converter'
  s.description = 'Convert thorough API documentation generated with Doxygen to neat AsciiDoc format.'
  s.license = 'MIT'

  s.add_runtime_dependency 'nokogiri', '~> 1.6.7'

  s.files = Dir['lib/*', 'lib/*/**']
  s.executables = ['doxml2asciidoc']
  s.require_paths = ['libs']
end

