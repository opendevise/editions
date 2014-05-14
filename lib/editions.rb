module Editions
  LIBDIR = File.expand_path '..', __FILE__
  $:.delete LIBDIR
  $:.unshift LIBDIR
  DATADIR = File.join (File.dirname LIBDIR), 'data'
end
require_relative 'editions/version'
require_relative 'editions/core_ext'
require_relative 'editions/model'
require_relative 'editions/hub'
require_relative 'editions/repository_manager'
