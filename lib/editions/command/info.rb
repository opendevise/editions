desc 'Print a summary of the environment'
command :info do |cmd|; cmd.instance_eval do
  config_required
  action do |global, opts, args, config = global.config|
    color 'Profile: ', :bold
    say config.profile
    color 'Publication: ', :bold
    say '%s <%s>' % [config.pub_name, config.pub_url]
    color 'Producer: ', :bold
    say config.pub_producer
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
