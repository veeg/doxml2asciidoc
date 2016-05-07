require 'fileutils'

module Doxml2AsciiDoc
class Converter

  @@verbose = false

  def initialize opts = {}
    @root = nil
  end

  def process root
    @root = root

    str = convert

    @root = nil

    str
  end

  def verbose msg
    if @@verbose
      puts msg
    end
  end

  def convert
    verbose "Converting"

    hsh = parse @root
    ad = AsciidocOutput.new hsh
    ad.generate
  end

  def self.parse_file infile
    str = ::IO.read infile
    xmldoc = ::Nokogiri::XML::Document.parse str
    converter = Converter.new xmldoc
    converter.verbose "Parsing input file: #{infile}"
    converter.parse(xmldoc.root)
  end

  def parse root
    @root = root
    hsh =  nil
    if @root.name.eql? "doxygenindex"
      verbose "Input root is DoxygenIndex"
      hsh = parse_doxygenindex @root
    elsif @root.name.eql? "doxygen"
      verbose "Input root is Doxygen"
      compound_def = @root.at_xpath('//compounddef')
      case compound_def['kind']
      when 'file'
        hsh = parse_doxygenfile @root
      else
        raise "Unknown/unhandled compound_def " + compound_def['kind']
      end
    else
      raise "Unhandled/Unknown root element: " + @root.name
    end

    hsh
  end

  # Assume the input doc rootelement is 'doxygenindex'
  def parse_doxygenindex root

    hsh = {:name => "Index",
           :files => [],
    }

    root.xpath('//compound').each do |compound|

      xmldir = ::FileUtils.pwd
      filename = "#{compound['refid']}.xml"
      filepath = File.join xmldir, filename

      verbose "Parsing compound... Kind: " + compound['kind']

      case compound['kind']
      when 'file'
        h = Converter.parse_file filepath
        hsh[:files] << h
      when 'struct'
      when 'dir'
        # Silently ignore this compound - we dont care about it.
      else
        $stderr.puts "Unhandled doxygenindex compound kind: " + compound['kind']
      end
    end

    hsh
  end

  def parse_doxygenfile root
    compound = root.at_xpath '//compounddef'

    hsh = {:name => compound.element_children.at_xpath('//compoundname').text,
           :id => compound['id'],
           :language => compound['language'],
           :functions => [],
           :enums => [],
           :typedefs => [],
           :vars => []
          }

    compound.xpath('./sectiondef').each do |section|
      verbose "Parsing sectiondef kind " + section['kind']
      case section['kind']
      when 'define'
        parse_sectiondef_define section
      when 'func'
       ret = parse_sectiondef_func section
       hsh[:functions].concat ret[:functions]
      when 'typedef'
        ret = parse_sectiondef_typedef(section)
        hsh[:typedefs].concat(ret)
      when 'enum'
        ret = parse_sectiondef_enum(section)
        hsh[:enums].concat(ret)
      when 'var'
        ret = parse_sectiondef_var(section)
        hsh[:vars].concat(ret)
      else
        raise "Unhandled section kind " + section['kind']
      end
    end

    hsh
  end

  def parse_sectiondef_define section
    # TODO: Implement me
    $stderr.puts "WARNING: sectiondef define not implemented."
    []
  end

  def parse_sectiondef_var section
    # TODO: implement me
    $stderr.puts "WARNING: sectiondef var not implemented."
    []
  end

  def parse_sectiondef_typedef section
    typedefs = []

    section.xpath('./memberdef').each do |member|
      case member['kind']
      when 'typedef'
        hsh = {}
        hsh[:name] = member.at_xpath('./name').text
        hsh[:type] = member.at_xpath('./type').text
        detail = member.at_xpath('./detaileddescription')
        if detail
          hsh[:doc] = detail.text
        end
        typedefs << hsh
      else
        raise "member kind not typedef in sectiondef typedef: #{meber['kind']}"
      end
    end

    typedefs
  end

  def parse_sectiondef_enum section
    enums = []
    section.xpath('./memberdef').each do |member|
      case member['kind']
      when 'enum'
        hsh = {}
        hsh[:name] = member.at_xpath('./name').text

        brief = member.at_xpath('./briefdescription/para')
        if brief
          hsh[:doc] = brief.text
        end

        hsh[:enums] = []
        member.xpath('./enumvalue').each do |enum|
          e = {}
          e[:name] = enum.at_xpath('./name').text
          # Get the first para in briefdescription
          brief = enum.at_xpath('./briefdescription/para')
          if brief
            # brief is contained in one or more para children?
            e[:doc] = brief.text
          end
          hsh[:enums] << e
        end
        enums << hsh
      else
        raise "member kind not enum in sectiondef enum: (#{member['kind']}"
      end
    end

    enums
  end

  def parse_sectiondef_func section
    functions = []
    section.xpath('./memberdef').each do |member|
      case member['kind']
      when 'function'
        hsh = {}
        hsh[:function_name] = member.at_xpath('./name').text
        hsh[:return_type] = member.at_xpath('./type').text
        hsh[:definition] = member.at_xpath('./definition').text
        hsh[:argsstring] = member.at_xpath('./argsstring').text

        params = []
        member.xpath('./param').each do |param|
          param = {:type => param.at_xpath('./type').text,
                   :declname => param.at_xpath('./declname').text}
          params.push param
        end
        hsh[:params] = params
        hsh[:return] = []
        detail = member.at_xpath('./detaileddescription')
        if detail
          hsh[:detail] = []
          #detail contains one or more <para></para> entries
          # The first entry contains the long ass description, IF IT EXISTS
          detail.xpath('./para').each do |para|
            if para.element_children.size == 0
              # Detailed description
              hsh[:detail].push :type => :text, :value => para.text
            else
              # Iterate all children of para
              para.children.each do |child|
                if child.text?
                  hsh[:detail].push :type => :text, :value => child.text

                elsif child.element? and child.name.eql? "programlisting"
                  # CODE!
                  codeblock = ""
                  child.children.each do |codeline|
                    line = ""
                    codeline.children.each do |e|
                      line = parse_codeline e, line
                    end
                    if not line.empty?
                      line += "\n"
                    end
                    codeblock += line
                  end
                  hsh[:detail].push :type => :code, :value => codeblock

                elsif child.element? and child.name.eql? "itemizedlist"
                  listitems = child.xpath('./listitem')
                  next if listitems.nil?

                  list = []
                  listitems.each do |item|
                    list << item.at_xpath('./para').text
                  end
                  hsh[:detail].push :type => :list, :value => list

                elsif child.element? and child.name.eql? "parameterlist"
                  # Parameters
                  parameters = child.xpath('./parameteritem')
                  next if parameters.nil?

                  parameters.each do |parameteritem|
                    name = parameteritem.at('./parameternamelist/parametername')
                    next if name.nil?
                    next if name.text.empty?

                    # Find the associated entry in the param list
                    hsh[:params].each do |param|
                      if param[:declname].eql? name.text
                        # Do the remainder of the mappings
                        param[:direction] = parameteritem.at('./parameternamelist/parametername')['direction']
                        param[:description] = parameteritem.at('./parameterdescription/para').text
                      end
                    end
                  end

                elsif child.element? and child.name.eql? 'simplesect'
                  case child['kind']
                  when "return"
                    hsh[:return] <<  child.text
                  else
                    $stderr.puts 'detailed description -> simplesect kind not handled: ' + child['kind']
                  end

                else
                  $stderr.puts "detailed description parameter child not handled: " + child.name
                end
              end

            end
          end
        end

        hsh[:brief] = member.at_xpath('./briefdescription').text

        functions.push hsh
      else
        raise "Unhandled sectiondef->memberdef kind " + member['kind']
      end
    end

    {:functions => functions}
  end

  def parse_codeline element, line
    if element.text?
      line += element.text
    elsif element.element? and element.name.eql? "sp"
      line += " "
    elsif element.element? and element.name.eql? "highlight"
      element.children.each do |c|
        line = parse_codeline c, line
      end
    else
      $stderr.puts "Codeline element not handled: " + e.name
    end
    line
  end

end

  class AsciidocOutput
    def initialize hsh = {}
      @str = ""
      @files = []
      @name = hsh[:name]

      if hsh.has_key?(:files)
        @files = hsh[:files]
      else
        @files << hsh
      end
    end

    def generate

      @str = "= #{@name} API Documentation\n"
      @str += ":source-highlighter: coderay\n"
      @str += ":toc: left\n"
      @str += "\n"

      #output_typedefs


      output_enums

      @str += "== Functions\n"
      @str += "\n"

      @files.each do |hsh|
        hsh[:functions].each do |func|
          single_function func
        end
      end
      @str += "\n"
    end

    def output_typedefs
      typedefs = []
      @files.each do |hsh|
        if hsh.has_key? :typedefs
          hsh[:typedefs].each do |typedef|
            typedefs << typedef
          end
        end
      end
      if typedefs.length > 0
        @str += "== Typedefs\n"
        @str += "\n"
        typedefs.each do |typedef|
          single_typedef typedef
        end
        @str += "\n"
      end
    end

    def output_enums
      @str += "== Enums\n"
      @str += "\n"
      @files.each do |hsh|
        hsh[:enums].each do |enum|
          single_enum enum
        end
      end
      @str += "\n"
    end

    def single_typedef typedef
      @str += "=== #{typedef[:name]}\n"
      @str += "\n"
      @str += "[horizontal]\n"
      @str += "#{typedef[:type]} -> #{typedef[:name]}:: #{typedef[:doc]}\n"
    end

    def single_enum enum
      @str += "=== #{enum[:name]}\n"
      @str += "\n"
      @str += enum[:doc] if enum[:doc]
      @str += "\n"
      @str += "[horizontal]\n"
      enum[:enums].each do |e|
        doc = e[:doc]
        doc ||= "No documentation entry."
        @str += "#{e[:name]}:: #{doc}\n"
      end
      @str += "\n"
    end

    def single_function func

      @str += "=== #{func[:function_name]}\n"
      @str += "\n"
      @str += "[cols='h,5a']\n"
      @str += "|===\n"
      @str += "| Description\n"
      @str += "| #{func[:brief]}\n"
      @str += "\n"

      @str += "| Signature \n"
      @str += "|\n"
      @str += "[source,C]\n"
      @str += "----\n"
      @str += "#{func[:definition]} #{func[:argsstring]}\n"
      @str += "----\n"
      @str += "\n"

      @str += "| Parameters\n"
      @str += "|\n"
      func[:params].each do |param|
        @str += "#{parameter_direction_string param}`#{param[:type]} #{param[:declname]}`::\n"
        @str += "#{param[:description]}\n"
      end
      @str += "\n"

      if func[:return].length > 0
        @str += "| Return\n"
        @str += "| "
        func[:return].each do |ret|
          @str += "* #{ret} \n"
        end
        @str += "\n"
      end

      # All entries have one '\n' :text entry - Ignore this section if so.
      if func[:detail].length > 2
        @str += "| Details / Examples \n"
        @str += "|\n"
        func[:detail].each do |detail|
          if detail[:type] == :code
            @str += "----\n"
            @str += "#{detail[:value]}\n"
            @str += "----\n"
          elsif detail[:type] == :text
            @str += "#{detail[:value]}\n"
          elsif detail[:type] == :list
            @str += "\n"
            detail[:value].each do |txt|
              @str += " * #{txt}\n"
            end
            @str += "\n\n"
          end
        end
        @str += "\n"
      end

      @str += "|===\n"
      @str += "\n"
    end

    def parameter_direction_string param
      if param[:direction]
        "*#{param[:direction]}* "
      else
        ""
      end
    end
  end # AsciidocOutput

end
