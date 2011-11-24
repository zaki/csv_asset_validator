# encoding: utf-8

require 'rubygems'
require 'csv'
require 'yaml'
require 'progressbar'

#{{{ - Formatters
# BaseFormatter is a simple base for future formatters
# A Formatter responds to the following methods
# * initialize(options)
# * add_message(entity, type, file, message)
# * output()
class BaseFormatter
  def initialize(options={})
    @messages = {}
  end

  def add_message(entity, type, file, message='')
    @messages[entity] ||= []
    @messages[entity] << [type, file, message]
  end
end

# SimpleFormatter
# A plain text printer for the console with colorful output. This is the default formatter.
class SimpleFormatter < BaseFormatter
  def output
    colors = { :missing => :red, :invalid => :yellow }
    @messages.each_pair do |entity, messages|
      puts "Found #{messages.length} problems for #{entity}"
      messages.each do |type, file, message|
        puts color_str(type.to_s.upcase, colors[type] || :yellow) + ' ' + file + ' ' + message
      end
    end
    puts "-----------------------------------"
  end
end

# HtmlFormatter
# A HTML formatter that outputs a single HTML file named asset_validation.html into Rails.root
# The template for this formatter is located in lib/assets/asset_validation.html.erb
class HtmlFormatter < BaseFormatter
  def output
    require 'erubis'
    template = File.read(Rails.root.join('lib', 'assets', 'asset_validation.html.erb'))
    File.open(Rails.root.join('asset_validation.html'), 'w+') do |file|
      eruby = Erubis::Eruby.new(template)
      file.puts eruby.evaluate(:messages => @messages)
    end
  end
end
#}}}

# AssetValidator is a simple utility to check whether assets exist and satisfy basic criteria
# such as dimensions or file size.
# This helper works with a list of items in a csv seed file and its configuration file needs
# to be placed in config/asset_validations.rb
# @example config/asset_validations.rb
#   entity_list 'users', 'db/data/01.users.csv' do |user|
#     on_path 'public/images/users' do
#       validate "#{item['id']}/#{item['name']}.png", '60x60', 3072
#     end
#   end
class AssetValidator

  #{{{ - Descriptive methods
  # entity_list
  # Sets the entity list to work with and iterates over the elements in that list
  # @param [string] name A name for this entity list, such as 'Users'
  # @param [string] csv_path The path to the CSV file containing a list of entities
  def entity_list(name, csv_path, &block)
    @messages = []
    @progress = ProgressBar.new(name, 100)
    @entity = name
    lines = IO.read(csv_path).split(/[\r\n]+/).delete_if{|r| r.lstrip[0, 1] == "#" or r.lstrip[0,2] == '"#' or r.strip.blank? }
    entities = FasterCSV.parse(lines.join("\n"), :headers => true, :skip_blanks => true)
    progress, count = 0, entities.length
    entities.each do |row|
      yield row
      progress += 1
      @progress.set( progress.to_f / count.to_f * 100 )
    end
    @progress.finish
  end

  # on_path
  # Sets the base path for asset checking
  # @param [string] path A base path to check asset files in
  def on_path(path, &block)
    @path = path
    yield
  ensure
    @path = nil
  end

  # validate
  # Runs validations on a single file
  # @param [string] file_name The name of the file to check with extension
  # @param [string] dimensions optional The required dimensions in '<WIDTH>x<HEIGHT>' format, such as '40x120'
  # @param [integer] size optional A maximum allowed file size in bytes
  # validate currently checks existence for any file type, however dimension and file size checking
  # is only effective for images of type GIF, JPG and PNG.
  def validate(file_name, dimension=nil, size=0)
    type = File.extname(file_name)
    type = type[1..-1].upcase
    path = Rails.root.join(@path, file_name)
    if File.exist?(path)
      if %w(GIF JPG PNG).include?(type)
        t,d,s = %x(identify -format "%m %wx%h %b" "#{path}").split(/ /)

        s = s[0..-2].to_i

        @formatter.add_message(@entity, :invalid,  path, "Dimension should be #{dimension} but it was #{d}") unless dimension == d
        @formatter.add_message(@entity, :invalid,  path, "Type should be #{type} but it was #{t}") unless type == t

        if size != 0
          @formatter.add_message(@entity, :invalid, path, "Size should be below #{size / 1024.0}kB but was #{s / 1024.0}kB") unless size > s
        end
      end
    else
      @formatter.add_message(@entity, :missing, path)
    end
  end
  #}}}

  # run
  # Runs the full validation suite using the configuration file 'config/asset_validations.rb'
  # Usage:
  #   require 'asset_validator'
  #   AssetValidator.new.run
  def run(format=:simple)
    @formatter = case format
                 when :html
                   HtmlFormatter.new
                 else
                   SimpleFormatter.new
                 end

    validation_file = Rails.root.join('config', 'asset_validations.rb')
    instance_eval(validation_file.read, validation_file) if validation_file.file?
    @formatter.output
  end
end

