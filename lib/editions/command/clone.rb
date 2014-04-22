desc 'Clone the article repositories'
command :clone do |cmd|; cmd.instance_eval do
  flag :C, :directory,
    arg_name: '<directory>',
    desc: 'Create and switch to <directory>',
    required: true,
    default_value: '.'

  flag :p, :period,
    arg_name: '<date>',
    desc: %(The period of the issue (e.g., #{Time.now.strftime '%Y-%m'})),
    required: true,
    default_value: (Time.now.strftime '%Y-%m')

  config_required

  action do |global, opts, args, config = global.config|
    # QUESTION should we be more intelligent about how the working directory is built?
    edition_slug = global.profile ? %(#{global.profile}-#{opts.period}) : opts.period

    clone_url = %(https://#{config.hub_access_token}:x-oauth-basic@github.com/#{config.hub_organization}/#{edition_slug})
    clone_dir = edition_slug
    say %(Cloning repository #{config.hub_organization}/#{edition_slug} to #{clone_dir}...)
    if Rugged.features.include? :https
      Rugged::Repository.clone_at clone_url, clone_dir
    else
      Open3.popen3 %(git clone --recursive #{clone_url} #{clone_dir}) do |i, o, e, t|
        t.value
      end
    end

=begin
    work_dir = File.expand_path(File.join opts.directory, edition_slug)
    FileUtils.mkdir_p work_dir unless File.directory? work_dir
    Dir.chdir work_dir

    gh = Octokit::Client.new access_token: config.hub_access_token
    gh.auto_paginate = true

    repo_prefix = %(#{edition_slug}-)
    # IMPORTANT repos method doesn't work here, must use org_repos method
    gh.org_repos(config.hub_organization, type: config.repository_access).select {|repo| repo.name.start_with? repo_prefix }.each do |repo|
      say %(Cloning repository #{repo.full_name} to #{File.join Dir.pwd, repo.name})
      #log 'git clone', repo.full_name, (File.join Dir.pwd, repo.name)
      clone_url = %(https://#{config.hub_username}:#{config.hub_access_token}@github.com/#{repo.full_name}.git)
      clone_dir = repo.name
      if Rugged.features.include? :https
        Rugged::Repository.clone_at clone_url, clone_dir
      else
        Open3.popen3 %(git clone #{clone_url} #{clone_dir}) do |i, o, e, t|
          t.value
        end
        Rugged::Repository.new clone_dir
      end
    end
=end
  end
end; end
