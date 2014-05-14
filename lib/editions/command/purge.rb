desc 'Remove the article repositories for an edition'
command :purge do |cmd|; cmd.instance_eval do
  flag :e, :edition,
    arg_name: '<edition>',
    desc: 'The volume and issue number of this edition (e.g., 5.1)',
    required: true,
    # Editions::EditionNumber parses volume and issue number parts into an Array
    type: Editions::EditionNumber,
    must_match: Editions::EditionNumberRx

  flag :a, :authors,
    arg_name: '<login>[,<login>]*',
    desc: 'A comma-separated list of usernames of the contributing authors',
    type: Array

  config_required

  action do |global, opts, args, config = global.config|
    hub = Editions::Hub.connect config, %w(repo delete_repo)
    edition = Editions::Edition.new opts.edition, nil, nil, (Editions::Publication.from config)
    manager = Editions::RepositoryManager.new hub, config.git_name, config.git_email, config.repository_access
    if opts.authors.nil_or_empty?
      manager.delete_repositories_for_edition config.hub_organization, edition, batch: global.batch
    else
      manager.delete_article_repositories config.hub_organization, opts.authors, edition, batch: global.batch
    end
  end
end; end
