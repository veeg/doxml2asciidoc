require 'nokogiri'
require_relative 'doxml2asciidoc/converter'

module Doxml2AsciiDoc

  def self.convert str, opts = {}
    xmldoc = ::Nokogiri::XML::Document.parse str
    raise 'Not a parsable document' unless (root = xmldoc.root)
    doxml = Converter.new opts
    doxml.process root
  end

  def self.convert_file infile, opts = {}
    outfile = if (ext = ::File.extname infile)
      %(#{infile[0...-ext.length]}.adoc)
    else
      %(#{inile}.adoc)
    end

    str = ::IO.read infile
    output = convert str, opts
    ::IO.write outfile, output
    nil
  end

end
