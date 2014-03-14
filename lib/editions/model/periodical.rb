module Editions
class Periodical
  class << self
    def from config
      Periodical.new config.pub_name, config.pub_url, config.pub_producer, config.profile
    end
  end

  attr_reader :name
  attr_reader :url
  attr_reader :producer
  attr_reader :slug

  def initialize name, url, producer, slug = nil
    @name = name
    @url = url
    @producer = producer
    @slug = slug
  end

  alias :title :name
end
end
