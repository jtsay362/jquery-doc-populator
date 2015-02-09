require 'json'
require 'fileutils'
require 'pathname'
require 'uri'
require 'nokogiri'

class JqueryDocPopulator
  def initialize(input_path, output_filename)
    @input_path = input_path
    @output_filename = output_filename

    @output_path = "out"
    @full_output_filename = File.join(@output_path, @output_filename)
  end


  def populate
    @all_kinds = {}
    File.open(@full_output_filename, 'w:UTF-8') do |out|
      out.write <<-eos
{
  "metadata" : {
    "mapping" : {
      "_all" : {
        "enabled" : false
      },
      "properties" : {
        "name" : {
          "type" : "string",
          "index" : "analyzed"
        },
        "title" : {
          "type" : "string",
          "index" : "analyzed"
        },
        "kind" : {
          "type" : "string",
          "index" : "no"
        },
        "url" : {
          "type" : "string",
          "index" : "no"
        },
        "summaryHtml" : {
          "type" : "string",
          "index" : "no"
        },
        "descriptionHtml" : {
          "type" : "string",
          "index" : "no"
        },
        "sampleHtml" : {
          "type" : "string",
          "index" : "no"
        },
        "returnType" : {
          "type" : "string",
          "index" : "no"
        },
        "deprecated" : {
          "type" : "string",
          "index" : "no"
        },
        "removed" : {
          "type" : "string",
          "index" : "no"
        },
        "signatures" : {
          "type" : "object",
          "enabled" : false
        },
        "examples" : {
          "type" : "object",
          "enabled" : false
        }
      }
    }
  },
  "updates" : [
    eos

      write_doc_index(out)
      out.write("]\n}")
    end

    puts "All kinds = " + @all_kinds.keys.join(',')
  end

  private

  def write_doc_index(out)
    @first_doc = true
    Dir.entries(File.join(@input_path, 'entries')).each do |entry|
      next unless entry.end_with?('.xml')

      #next unless entry == 'jQuery.browser.xml'

      puts "Parsing '#{entry}' ..."

      parse_entry_file(out, File.join(@input_path, 'entries', entry))

      puts "Done parsing '#{entry}'."
    end
  end


  def extract_arg_types(arg)
    type_attr = (arg.attr('type').strip rescue nil)

    if type_attr
      [type_attr]
    else
      (arg > 'type').map do |type_node|
        type_node.attr('name').strip
      end
    end
  end


  def extract_arg_or_property(arg)
    doc = {
      name: arg.attr('name').strip,
      possibleTypes: extract_arg_types(arg),
      optional: ((arg.attr('optional').strip == 'true') rescue false),
      descriptionHtml: ((arg > 'desc').inner_html.strip rescue nil)
    }

    added = arg.attr('added')

    if added && !added.empty?
      doc[:added] = added
    end

    property_nodes = (arg > 'property')

    if property_nodes.length > 0
      doc[:properties] = property_nodes.map do |prop|
        extract_arg_or_property(prop)
      end
    end

    arg_nodes = (arg > 'argument')

    if arg_nodes.length > 0
      doc[:arguments] = arg_nodes.map do |argument|
        extract_arg_or_property(argument)
      end
    end

    doc
  end

  def compute_recognition_key(kind)
    'com.solveforall.recognition.programming.web.javascript.jquery.' + kind.capitalize
  end

  def parse_entry_file(out, filename)
    File.open(filename) do |f|
      doc = Nokogiri::XML(f)

      doc.css('entry').each do |entry|
        kind = entry.attr('type').strip

        @all_kinds[kind] = true

        url = ('https://api.jquery.com/' + File.basename(filename)).gsub(/\.xml$/, '/')

        output_doc = {
          name: entry.attr('name').strip,
          url: url,
          title: (entry > 'title').text.strip,
          kind: entry.attr('type').strip,
          returnType: (entry.attr('return').strip rescue nil),
          summaryHtml: (entry > 'desc').inner_html.strip,
          descriptionHtml: (entry > 'longdesc').inner_html.strip,
          sampleHtml: ((entry > 'sample').inner_html.strip rescue nil),
          deprecated: (entry.attr('deprecated').strip rescue nil),
          removed: (entry.attr('removed').strip rescue nil),
          signatures: (entry > 'signature').map do |sig|
            {
              added: (sig > 'added').text,
              args: (sig > 'argument').map do |arg|
                extract_arg_or_property(arg)
              end
            }
          end,
          examples: (entry > 'example').map do |example|
            {
              descriptionHtml: (example > 'desc').inner_html.strip,
              codeHtml: (example > 'code').inner_html.strip,
              exampleHtml: (example > 'html').text().strip
            }
          end,
          categories: (entry > 'category').map do |category|
            category.attr('slug')
          end,
          recognitionKeys: [compute_recognition_key(kind)]
        }

        if @first_doc
          @first_doc = false
        else
          out.write(",\n")
        end

        out.write(JSON.pretty_generate(output_doc))
      end
    end
  end
end

DOWNLOAD_PATH = './out'
REMOTE_GIT_URL = 'https://github.com/jquery/api.jquery.com'
input_path = File.join(DOWNLOAD_PATH, 'api.jquery.com')
is_input_path_explicit = nil
output_filename = 'jquery_doc.json'
download = true

ARGV.each do |arg|
  if arg == '-d'
    download = true
    input_path = File.join(DOWNLOAD_PATH, 'api.jquery.com')
  elsif is_input_path_explicit
    output_filename = arg
  else
    input_path = arg
    is_input_path_explicit = true
  end
end

puts "input_path = #{input_path}"

FileUtils.mkdir_p("out")

if download
  system("cd #{DOWNLOAD_PATH}; git clone #{REMOTE_GIT_URL}")
end

populator = JqueryDocPopulator.new(input_path, output_filename)

populator.populate()
system("bzip2 -kf out/#{output_filename}")