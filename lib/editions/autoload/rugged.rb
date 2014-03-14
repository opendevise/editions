require 'rugged'
unless Rugged.respond_to? :features
  def Rugged.features
    []
  end
end
require 'tmpdir'
require_relative '../refined'
