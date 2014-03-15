module Editions
class Hub
  class << self
    # QUESTION add argument of scopes to verify?
    def connect credentials, require_scopes = nil
      if credentials.is_a? ::OpenStruct
        client = if credentials.hub_netrc
          ::Octokit::Client.new netrc: true
        else
          ::Octokit::Client.new access_token: credentials.hub_access_token
        end
        # verify authentication credentials by attempting to fetch the current user
        begin
          client.user
        rescue ::Octokit::Unauthorized
          exit_now! %(invalid access token\nPlease run '#{exe_name} config' again to properly configure your environment.)
        end
        unless require_scopes.nil_or_empty? || (missing_scopes = (require_scopes - client.scopes)).empty?
          exit_now! %(#{client.user.login} is missing the following authorization scopes necessary to perform this operation: #{missing_scopes * ', '})
        end
        return client
      elsif credentials.is_a? ::Hash
        client = if (credentials.key? :netrc)
          ::Octokit::Client.new netrc: true
        else
          ::Octokit::Client.new login: credentials[:username], password: credentials[:password]
        end
        return client
      end

      raise ::ArgumentError, 'Invalid credentials argument'
    end
  end
end
end
