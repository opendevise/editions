require 'gli'
require_relative 'gli_ext'
require 'highline/import'
require 'commander/user_interaction'
require 'safe_yaml'

autoload :Base64, 'base64'
autoload :DateTime, 'date'
autoload :FileUtils, 'fileutils'
autoload :Open3, 'open3'
autoload :Octokit, File.expand_path('autoload/octokit.rb', File.dirname(__FILE__))
autoload :Refined, File.expand_path('autoload/rugged.rb', File.dirname(__FILE__))
autoload :Rugged, File.expand_path('autoload/rugged.rb', File.dirname(__FILE__))

include GLI::App
include Commander::UI

# restore top-level color function
def colorize *args
  $terminal.color(*args)
end

program_desc 'create and publish editions of a publication from articles composed in AsciiDoc'
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
  desc: 'Run using the specified configuration profile. (Also used as the prefix for this publication\'s resources).',
  default_value: ENV['EDITIONS_PROFILE']

switch :y, :batch,
  desc: 'Assume that the answer to any question which would be asked is \'y\' (yes)',
  default_value: false

# Hooks
pre do |global, cmd, opts, args|
  conf_basename = global.profile ? %(.editions-#{global.profile}.yml) : '.editions.yml'
  # NOTE can't use global.config_file since it's a built-in function name in gli
  global.conf_file = conf_file = File.expand_path conf_basename, ENV['HOME']
  global.config = OpenStruct.new(YAML.load_file conf_file, safe: true) if File.exist? conf_file
  if (cmd.respond_to? :config_required?) && cmd.config_required? && !global.config
    exit_now! %(#{global.profile || 'default'} profile does not exist\nPlease run '#{exe_name} config' to configure your environment.)
  end
  true
end

on_error do |ex|
  case ex
  when Interrupt
    # add extra endline if Ctrl+C is used
    $terminal.newline
    false
  when ArgumentError, NameError
    puts ex.message
    puts ex.backtrace
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
require_relative 'command/build'
