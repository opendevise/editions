desc 'Print a summary of the environment'
command :info do |cmd|
  cmd.action do |global, opts, args|
    unless (config = global.config)
      exit_now! color(%(error: #{global.profile || 'default'} profile does not exist. Please run `config' to configure your environment.), :red)
    end
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
end
