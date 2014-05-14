require 'octokit'
module Octokit
  class Client
    module HostInfo
      def host
        @host ||= (URI @web_endpoint).host
      end
    end
  
    include Octokit::Client::HostInfo
  end
end
