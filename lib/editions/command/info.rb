desc 'Print a summary of the environment'
command :info do |cmd|; cmd.instance_eval do
  config_required
  action do |global, opts, args, config = global.config|
    edition = Editions::Edition.new '1.3', nil, nil, (Editions::Publication.from config)
    color 'Profile: ', :bold
    say config.profile
    color 'Publication: ', :bold
    if config.pub_handle
      say '%s (%s) <%s>' % [config.pub_name, config.pub_handle, config.pub_url]
    else
      say '%s <%s>' % [config.pub_name, config.pub_url]
    end
    color 'Publisher: ', :bold
    say config.pub_publisher
    if config.pub_description
      color 'Description: ', :bold
      say config.pub_description
    end
    color 'Organization: ', :bold
    say config.hub_organization
    color 'Username: ', :bold
    say config.hub_username
    color 'Editor: ', :bold
    say '%s <%s>' % [config.git_name, config.git_email]
    color 'Repository Access: ', :bold
    say config.repository_access.to_s
  end
end; end
