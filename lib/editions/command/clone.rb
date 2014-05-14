desc 'Clone the repositories for an edition'
arg_name '[repository_url]'
command :clone do |cmd|; cmd.instance_eval do
  flag :e, :edition,
    arg_name: '<edition>',
    desc: 'The volume and issue number of this edition (e.g., 5.1)',
    # Editions::EditionNumber parses volume and issue number parts into an Array
    type: Editions::EditionNumber,
    must_match: Editions::EditionNumberRx

  #flag :C, :directory,
  #  arg_name: '<directory>',
  #  desc: 'Create and switch to <directory>',
  #  required: true,
  #  default_value: '.'

  #config_required

  # QUESTION should we be more intelligent about how the working directory is built?
  action do |global, opts, args, config = global.config|
    if args.size == 1
      manager = nil
      spine_clone_url = repo_qname = args[0]
      repo_name = File.basename spine_clone_url, '.git'
    elsif config && opts.edition
      hub = Editions::Hub.connect config
      edition = Editions::Edition.new opts.edition, nil, nil, (Editions::Publication.from config)
      manager = Editions::RepositoryManager.new hub, config.git_name, config.git_email, config.repository_access
      repo_qname = %(#{config.hub_organization}/#{repo_name = edition.handle})
      spine_clone_url = manager.build_clone_url repo_qname
    else
      help_now! 'You must specify an edition number or the URL of a git repository to clone.'
    end

    if File.directory? repo_name
      help_now! %(The target directory already exists: #{repo_name})
    end

    repo_url_key = (spine_clone_url.start_with? 'https://') ? 'clone_url' : 'ssh_url'

    # TODO warn if the target directory already exists
    say %(Cloning repository #{repo_qname} to #{repo_name}...)

    # TODO warn if repository cannot be cloned
    Refined::Repository.clone_at spine_clone_url, repo_name

    Dir.chdir repo_name do
      # TODO warn gracefully if config.yaml is missing
      OpenStruct.new(YAML.load_file 'config.yml', safe: true).articles
        .map {|article|
          article_repo_url = article['repository'][repo_url_key]
          [(manager && repo_url_key == 'clone_url' ? (manager.inject_with_auth article_repo_url) : article_repo_url), article['local_dir']]
        }
        .each do |article_clone_url, article_clone_dir|
        # TODO warn if repository cannot be cloned
        Refined::Repository.clone_at article_clone_url, article_clone_dir, recursive: true
      end
    end
  end
end; end
