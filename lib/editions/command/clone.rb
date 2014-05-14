desc 'Clone the article repositories'
command :clone do |cmd|; cmd.instance_eval do
  flag :C, :directory,
    arg_name: '<directory>',
    desc: 'Create and switch to <directory>',
    required: true,
    default_value: '.'

  flag :e, :edition,
    arg_name: '<edition>',
    desc: 'The volume and issue number of this edition (e.g., 5.1)',
    required: true,
    # Editions::EditionNumber parses volume and issue number parts into an Array
    type: Editions::EditionNumber,
    must_match: Editions::EditionNumberRx

  #flag :p, :pubdate,
  #  arg_name: '<date>',
  #  desc: %(The publication date of the edition to clone (e.g., #{current_month = Time.now.strftime '%Y-%m'})),
  #  required: true,
  #  default_value: current_month

  config_required

  # QUESTION should we be more intelligent about how the working directory is built?
  # TODO option to clone using ssh URL
  action do |global, opts, args, config = global.config|
    hub = Editions::Hub.connect config
    edition = Editions::Edition.new opts.edition, nil, nil, (periodical = Editions::Periodical.from config)
    manager = Editions::RepositoryManager.new hub, config.git_name, config.git_email, config.repository_access
    repo_qname = %(#{config.hub_organization}/#{repo_name = edition.handle})
    spine_clone_url = manager.build_clone_url repo_qname

    # TODO warn if the target directory already exists
    say %(Cloning repository #{repo_qname} to #{repo_name}...)

    # TODO warn if repository cannot be cloned
    Refined::Repository.clone_at spine_clone_url, repo_name

    Dir.chdir repo_name do
      # TODO warn gracefully if config.yaml is missing
      OpenStruct.new(YAML.load_file 'config.yml', safe: true).articles
        .map {|article| [(manager.inject_with_auth article['repository']['clone_url']), article['localDir']] }
        .each do |article_clone_url, article_clone_dir|
        # TODO warn if repository cannot be cloned
        Refined::Repository.clone_at article_clone_url, article_clone_dir, recursive: true
      end
    end
  end
end; end
