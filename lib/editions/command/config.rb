desc 'Prepare your environment for using editions'
command :config do |cmd|; cmd.instance_eval do
  flag :u, :username,
    arg_name: '<login>',
    desc: 'the GitHub username (i.e., login) of the periodical\'s administrator',
    required: true

  flag :o, :org,
    arg_name: '<login>',
    desc: 'the GitHub organization for this periodical (defaults to the <username>)'

  #flag :s, :slug,
  #  arg_name: '<name>',
  #  desc: 'the slug for the periodical',
  #  required: true

  flag :t, :title,
    arg_name: '"<text>"',
    desc: 'the title of the periodical',
    required: true

  # TODO add more formal URL validation
  flag :h, :homepage,
    arg_name: '"<url>"',
    desc: 'the homepage URL of the periodical',
    required: true,
    must_match: /^https?:\/\/.*$/

  switch :p, :private,
    desc: 'Use private repositories on GitHub',
    negatable: false,
    default_value: false

  switch :netrc,
    desc: 'read credentials from your netrc file ($HOME/.netrc)',
    negatable: false,
    default_value: false

  action do |global, opts, args|
    if (username = opts.username).nil_or_empty?
      raise GLI::CommandException.new color(%(error: username cannot be empty\n), :red), self
    end

    # NOTE password can be an existing OAuth token, though it must have user priviledge
    # TODO password can also be set using OCTOKIT_PASSWORD environment variable
    passwd = (password %(Enter the GitHub password or OAuth token for #{username}: )).to_s unless opts.netrc

    #require 'octokit' unless defined? Octokit::Client
    gh = opts.netrc ? (Octokit::Client.new netrc: true) : (Octokit::Client.new login: username, password: passwd)
    user_resource = begin
      # NOTE verify authentication credentials by attempting to fetch the current user
      gh.user
    rescue Octokit::Unauthorized
      raise GLI::CommandException.new color(%(error: failed to authenticate #{username}\n), :red), self
    end

    access_token = begin
      # NOTE if the request for authorization fails, assume the password is the token
      (gh.create_authorization \
        scopes: %w(delete_repo repo user:email),
        note: %(editions-#{global.profile || 'global'}),
        note_url: opts.homepage).token
    rescue Octokit::UnprocessableEntity
      exit_now! color %(A personal access token named 'editions-#{global.profile || 'global'}' already exists for #{username}. Please navigate to Account Settings > Applications on GitHub and remove it.), :red
    rescue
      # QUESTION should we instead save the options Hash for Octokit::Client in the config?? (in this case netrc)
      say 'Cannot create personal access token with credentials provided. Assuming password provided is an OAuth token.'
      gh.instance_variable_get(:@password)
    end

    # TODO consider using a authorization from a registered application (would require additional client_id and client_secret arguments)
    # "Using application credentials makes anonymous API calls on behalf of an application in order to take advantage of the higher rate limit"
    #auth_resource = gh.create_authorization client_id: 'xxx', client_secret: 'xxx', scopes: ['delete_repo', 'repo', 'user:email'], idempotent: true

    # only needed if using token-based authentication
    #if user_resource.login != username
    #  raise GLI::CommandException.new color(%(error: username does match login of authentication token\n), :red), self
    #end

    config = {
      username: username,
      access_token: access_token,
      name: user_resource.name,
      email: ((email = user_resource.email).nil_or_empty? ? %(#{username}@users.noreply.github.com) : email),
      org: (opts.org || username),
      title: opts.title,
      homepage: opts.homepage,
      private: opts.private
    }

    File.open global.conf_file, 'w' do |f|
      f.write config.to_yaml.lines.entries[1..-1].map {|l| l[1..-1] }.join
    end
    say %(Wrote configuration to #{global.conf_file})
  end
end; end
