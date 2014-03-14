module Editions
  DATADIR = File.join File.dirname(File.dirname __FILE__), 'data'
end
require_relative 'editions/version'
require_relative 'editions/core_ext'
require_relative 'editions/model'
require_relative 'editions/hub'
require_relative 'editions/repository_manager'
