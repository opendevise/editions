require 'rugged'
class << Rugged; alias :features :capabilities; end unless Rugged.respond_to? :features
require 'tmpdir'
require_relative '../refined'
