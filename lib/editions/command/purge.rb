desc 'Remove the article repositories for an edition'
command :purge do |cmd|; cmd.instance_eval do
  flag :p, :period,
    arg_name: '<date>',
    desc: %(The period of the issue (e.g., #{Time.now.strftime '%Y-%m'})),
    default_value: (Time.now.strftime '%Y-%m')

  flag :a, :authors,
    arg_name: '<login>[,<login>]*',
    desc: 'A comma-separated list of usernames of the contributing authors',
    type: Array

  action do |global, opts, args|
    config = global.config
    exit_now! color(%(error: #{global.profile || 'global'} profile does not exist. Please run `config' to configure your environment.), :red) unless config
    #require 'octokit' unless defined? Octokit::Client

    gh = Octokit::Client.new access_token: config.access_token

    period = opts.period
    # TODO make this a utility method
    period_date = DateTime.parse %(#{period}-01)

    if opts.authors && !opts.authors.empty?
      opts.authors.each do |username|
        repo_name = '%s%s-%s' % [(global.profile ? %(#{global.profile}-) : ''), period, username]
        repo_qname = '%s/%s' % [config.org, repo_name]
        unless gh.repository? repo_qname
          say %(The repository #{repo_qname} does not exist. Skipping.)
          next
        end

        next unless global.y || (agree %(Are you *absolutely* sure you want to delete the repository #{repo_qname}? ))
        # NOTE If OAuth is used, 'delete_repo' scope is required
        gh.delete_repo repo_qname
      end
    else
      repo_prefix = '%s%s-' % [(global.profile ? %(#{global.profile}-) : ''), period]
      (repos = gh.repos config.org).each do |repo|
        if repo.name.start_with? repo_prefix
          next unless global.y || (agree %(Are you *absolutely* sure you want to delete the repository #{repo.full_name}? ))
          # NOTE If OAuth is used, 'delete_repo' scope is required
          gh.delete_repo repo.full_name
        end
      end
    end
  end
end; end
