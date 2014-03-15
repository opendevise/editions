desc 'Remove the article repositories for an edition'
command :purge do |cmd|; cmd.instance_eval do
  flag :p, :pubdate,
    arg_name: '<date>',
    desc: %(The publication date of the issue (e.g., #{current_month = Time.now.strftime '%Y-%m'})),
    default_value: current_month

  # TODO use a custom converter in the command spec to capture this data
  #flag :e, :edition,
  #  arg_name: '<edition>',
  #  desc: %(The volume and issue numbers of the issue (e.g., 5.1)),
  #  required: true,
  #  must_match: /^\d+\.\d+$/

  flag :a, :authors,
    arg_name: '<login>[,<login>]*',
    desc: 'A comma-separated list of usernames of the contributing authors',
    type: Array

  config_required

  action do |global, opts, args|
    config = global.config
    hub = Editions::Hub.connect config, %w(repo delete_repo)
    edition = Editions::Edition.new nil, nil, opts.pubdate, (periodical = Editions::Periodical.from config)
    manager = Editions::RepositoryManager.new hub, config.git_name, config.git_email, config.repository_access
    if opts.authors.nil_or_empty?
      manager.delete_all_article_repositories config.hub_organization, edition, batch: global.batch
    else
      manager.delete_article_repositories config.hub_organization, opts.authors, edition, batch: global.batch
    end
  end
end; end
