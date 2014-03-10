desc 'Print a summary of the environment'
command :dump do |cmd|
  cmd.action do |global, opts, args|
    config = global.config
    exit_now! color(%(error: #{global.profile || 'global'} profile does not exist. Please run `config' to configure your environment.), :red) unless config
    color 'Publisher: ', :bold
    say '%s <%s>' % [config.name, config.email]
    color 'Username: ', :bold
    say '%s' % config.username
    color 'Organization: ', :bold
    say '%s' % config.org
    color 'Repository Access: ', :bold
    say '%s' % (config.private ? 'private' : 'public')
    color 'Title: ', :bold
    say '%s' % config.title
    color 'Profile: ', :bold
    say '%s' % (global.profile || 'global')
    color 'Homepage: ', :bold
    say '%s' % config.homepage
  end
end
