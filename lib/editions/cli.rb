require 'gli'
require_relative 'gli_ext'
require 'highline/import'
require 'commander/user_interaction'
require 'yaml'

autoload :Base64, 'base64'
autoload :DateTime, 'date'
autoload :FileUtils, 'fileutils'
autoload :Octokit, File.expand_path('autoload/octokit.rb', File.dirname(__FILE__))
autoload :Rugged, File.expand_path('autoload/rugged.rb', File.dirname(__FILE__))

include GLI::App
include Commander::UI

program_desc 'publish periodicals from articles composed in AsciiDoc'
version Editions::VERSION

# GLI config
default_command :help
sort_help :manually
subcommand_option_handling :normal
use_openstruct true

# Custom types
accept Editions::EditionNumber do |value|
  Editions::EditionNumber.parse value
end

# Global arguments
flag :P, :profile,
  arg_name: '<name>',
  desc: 'Run using the specified configuration profile. (Also used as the prefix for this periodical\'s resources).',
  default_value: ENV['EDITIONS_PROFILE']

switch :y, :batch,
  desc: 'Assume that the answer to any question which would be asked is \'y\' (yes)',
  default_value: false

# Hooks
pre do |global, cmd, opts, args|
  conf_basename = global.profile ? %(.editions-#{global.profile}.yml) : '.editions.yml'
  # NOTE can't use global.config_file since it's a built-in function name in gli
  global.conf_file = conf_file = File.expand_path conf_basename, ENV['HOME']
  global.config = OpenStruct.new(YAML.load_file conf_file) if File.exist? conf_file
  true
end

on_error do |ex|
  if ex.is_a? Interrupt
    # add extra endline if Ctrl+C is used
    $terminal.newline
    false
  else
    true
  end
end

=begin
post do |global, cmd, opts, args|
end

around do |global, command, opts, args, code|
  code.call
end
=end

require_relative 'command/version'
require_relative 'command/console'
require_relative 'command/config'
require_relative 'command/info'
require_relative 'command/init'
require_relative 'command/purge'
require_relative 'command/clone'
