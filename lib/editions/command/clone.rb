desc 'Clone the article repositories'
command :clone do |cmd|; cmd.instance_eval do
  flag :C, :directory,
    arg_name: '<directory>',
    desc: 'Create and change to directory <directory>',
    required: true

  flag :p, :period,
    arg_name: '<date>',
    desc: %(The period of the issue (e.g., #{Time.now.strftime '%Y-%m'})),
    default_value: (Time.now.strftime '%Y-%m')

  config_required

  action do |global, opts, args, config = global.config|
    # QUESTION should we be more intelligent about how the working directory is built?
    edition_slug = global.profile ? %(#{global.profile}-#{opts.period}) : opts.period
    work_dir = File.expand_path(File.join opts.directory, edition_slug)
    FileUtils.mkdir_p work_dir unless File.directory? work_dir
    Dir.chdir work_dir

    gh = Octokit::Client.new access_token: config.hub_access_token
    gh.auto_paginate = true

    repo_prefix = %(#{edition_slug}-)
    # NOTE repos doesn't work here, must use org_repos
    gh.org_repos(config.org, type: (config.private ? :private : :public)).select {|repo| repo.name.start_with? repo_prefix }.each do |repo|
      #say %(Cloning repository #{repo.full_name} into #{File.join Dir.pwd, repo.name})
      log 'git clone', repo.full_name, (File.join Dir.pwd, repo.name)
      Rugged::Repository.clone_at %(https://#{config.username}:#{config.access_token}@github.com/#{repo.full_name}.git), repo.name
    end
  end
end; end
