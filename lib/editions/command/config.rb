desc 'Prepare your environment for using editions'
command :config do |cmd|; cmd.instance_eval do
  flag :u, :username,
    arg_name: '<login>',
    desc: 'the GitHub username (i.e., login) of the periodical\'s administrator',
    required: true

  flag :o, :org,
    arg_name: '<login>',
    #desc: 'the GitHub organization for this periodical (defaults to the <username>)'
    desc: 'the GitHub organization for this periodical',
    required: true

  flag :n, :name,
    arg_name: '"<text>"',
    desc: 'the name of the periodical',
    required: true

  # TODO add more formal URL validation
  flag :h, :homepage,
    arg_name: '"<url>"',
    desc: 'the homepage URL of the periodical',
    required: true,
    must_match: /^https?:\/\/.*$/

  flag :p, :producer,
    arg_name: '"<name>"',
    desc: 'the producer of the periodical',
    required: true

  switch :P, :private,
    desc: 'Use private repositories on GitHub',
    negatable: false,
    default_value: false

  switch :netrc,
    desc: 'read credentials from your netrc file ($HOME/.netrc)',
    negatable: false,
    default_value: false

  action do |global, opts, args|
    if (username = opts.username).nil_or_empty?
      raise GLI::CommandException.new 'username cannot be empty', self
    end

    # NOTE password can be an existing OAuth token, though it must have user priviledge
    # TODO password can also be set using OCTOKIT_PASSWORD environment variable
    passwd = (password %(Enter the GitHub password or OAuth token for #{username}: )).to_s unless opts.netrc

    hub = opts.netrc ? (Editions::Hub.connect netrc: true) : (Editions::Hub.connect username: username, password: passwd)
    user_resource = begin
      # NOTE verify authentication credentials by attempting to fetch the current user
      hub.user
    rescue Octokit::Unauthorized
      raise GLI::CommandException.new %(failed to authenticate #{username}), self
    end

    # TODO verify we have proper authorization scopes
    access_token_name = %(editions#{global.profile ? %[-#{global.profile}] : nil})
    access_token = begin
      # NOTE if the request for authorization fails, assume the password is the token
      (hub.create_authorization \
        scopes: %w(delete_repo repo user:email),
        note: access_token_name,
        note_url: opts.homepage).token
    rescue Octokit::UnprocessableEntity
      exit_now! %(A personal access token named '#{access_token_name}' already exists for #{username}.
Please navigate to Account Settings > Applications on GitHub and remove it.)
    rescue
      # QUESTION should we instead save the options Hash for Octokit::Client in the config?? (in this case netrc)
      say_warning 'Cannot create personal access token with credentials provided. Assuming password provided is an OAuth token.'
      hub.instance_variable_get :@password
    end

    # TODO consider using a authorization from a registered application (would require additional client_id and client_secret arguments)
    # "Using application credentials makes anonymous API calls on behalf of an application in order to take advantage of the higher rate limit"
    #auth_resource = hub.create_authorization client_id: 'xxx', client_secret: 'xxx', scopes: ['delete_repo', 'repo', 'user:email'], idempotent: true

    # only needed if using token-based authentication
    #if user_resource.login != username
    #  raise GLI::CommandException.new 'username does match login of authentication token', self
    #end

    # TODO validate the org is an organization on GitHub
    config = {
      profile: (global.profile || 'default'),
      hub_host: 'github',
      hub_username: username,
      hub_access_token: access_token,
      hub_netrc: opts.netrc,
      hub_organization: (opts.org || username),
      repository_access: (opts.private ? :private : :public),
      git_name: user_resource.name,
      git_email: ((email = user_resource.email).nil_or_empty? ? %(#{username}@users.noreply.github.com) : email),
      pub_name: opts.name,
      pub_url: opts.homepage,
      pub_producer: opts.producer
    }

    File.open global.conf_file, 'w', 0600 do |fd|
      fd.write config.to_yaml.lines.entries[1..-1].map {|ln| ln[1..-1] }.join
    end
    log 'wrote', global.conf_file
    say %(To make this your default profile, run this export command in your terminal:\n\n export EDITIONS_PROFILE=#{global.profile}\n\n) if global.profile
  end
end; end
