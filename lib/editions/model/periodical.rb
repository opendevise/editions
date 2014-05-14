module Editions
class Periodical
  class << self
    def from config
      Periodical.new config.pub_name, config.pub_handle, config.pub_url, config.pub_publisher, config.pub_description
    end
  end

  attr_reader :name
  attr_reader :handle
  attr_reader :url
  attr_reader :publisher
  attr_reader :description

  def initialize name, handle, url, publisher, description = nil
    @name = name
    @handle = handle
    @url = url
    @publisher = publisher
    @description = description
  end

  alias :title :name
end
end
