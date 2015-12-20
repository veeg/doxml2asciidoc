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
    hsh =  nil

    verbose "Converting"

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

    generate_asciidoc hsh
  end

  # Assume the input doc rootelement is 'doxygenindex'
  def parse_doxygenindex root 
    root.xpath('//compound').each do |compound|

      xmldir = ::FileUtils.pwd
      filename = "#{compound['refid']}.xml"
      filepath = File.join xmldir, filename

      verbose "Parsing compound... Kind: " + compound['kind']

      case compound['kind']
      when 'file'
        Doxml2AsciiDoc.convert_file filepath
      when 'struct'
      when 'dir'
        # Silently ignore this compound - we dont care about it.
      else
        STDERR.puts "Unhandled doxygenindex compound kind: " + compound['kind']
      end
    end
  end

  def parse_doxygenfile root 
    compound = root.at_xpath '//compounddef'

    hsh = {:name => compound.element_children.at_xpath('//compoundname').text,
           :id => compound['id'],
           :language => compound['language'],
           :functions => [],
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
        parse_sectiondef_typedef section
      else
        raise "Unhandled section kind " + section['kind']
      end
    end

    hsh
  end

  def parse_sectiondef_define section
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
        hsh[:return] = ""
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
                    hsh[:return] =  child.text
                  else
                    STDERR.puts 'detailed description -> simplesect kind not handled: ' + child['kind']
                  end
                  
                else
                  STDERR.puts "detailed description paramter child not handlled: " + child.name
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
      STDERR.puts "Codeline element not handled: " + e.name
    end
    line
  end


  def parse_sectiondef_typedef section
  end


  def generate_asciidoc hsh
    str = "= #{hsh[:name]} API Documentation\n"
    str += ":source-highlighter: coderay\n"
    str += "\n"

    str += "== Functions\n"
    str += "\n"
    
    hsh[:functions].each do |func|

      str += "== #{func[:function_name]}\n"
      str += "\n"
      str += "[cols='h,5a']\n"
      str += "|===\n"
      str += "| Description\n"
      str += "| #{func[:brief]}\n"
      str += "\n"

      str += "| Signature \n"
      str += "|\n"
      str += "[source,C]\n"
      str += "----\n"
      str += "#{func[:definition]} #{func[:argsstring]}\n" 
      str += "----\n"
      str += "\n"

      str += "| Parameters\n"
      str += "|\n"
      func[:params].each do |param|
        str += "#{parameter_direction_string param}`#{param[:type]} #{param[:declname]}`::\n"
        str += "#{param[:description]}\n"
      end
      str += "\n"

      str += "| Return\n"
      str += "| #{func[:return]} \n"
      str += "\n"

      # All entries have one '\n' :text entry - Ignore this section if so.
      if func[:detail].length > 2
        str += "| Details / Examples \n"
        str += "|\n"
        func[:detail].each do |detail|
          if detail[:type] == :code
          str += "----\n"
          str += "#{detail[:value]}\n"
          str += "----\n"
          elsif detail[:type] == :text
            str += "#{detail[:value]}\n"
          end
        end
        str += "\n"
      end
      str += "|===\n"
      str += "\n"
    end

    str
  end

  def parameter_direction_string param
    if param[:direction]
      "*#{param[:direction]}* "
    else
      ""
    end
  end

end
end
