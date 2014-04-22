desc 'Create and seed the article repositories for an edition'
command :init do |cmd|; cmd.instance_eval do
  flag :e, :edition,
    arg_name: '<edition>',
    desc: %(The volume and issue number of this edition (e.g., 5.1)),
    required: true,
    type: Editions::EditionNumber, # parses volume and issue number parts into Array
    must_match: Editions::EditionNumberRx

  flag :a, :authors,
    arg_name: '<login>[,<login>]*',
    desc: 'A comma-separated list of usernames of the contributing authors (will prompt if not specified)',
    type: Array

  flag :p, :pubdate,
    arg_name: '<date>',
    desc: %(The publication date of this edition (e.g., #{current_month = Time.now.strftime '%Y-%m'})),
    default_value: current_month

  config_required

  action do |global, opts, args, config = global.config|
    if opts.authors.nil_or_empty?
      opts.authors = ask 'Enter the username of each author: ', ->(s) { s.split /(?:\s*,\s*|\s+)/ }
      help_now! 'you must specify at least one username' if opts.authors.empty?
    end

    hub = Editions::Hub.connect config, %w(repo)
    edition = Editions::Edition.new opts.edition, nil, opts.pubdate, (periodical = Editions::Periodical.from config)
    manager = Editions::RepositoryManager.new hub, config.git_name, config.git_email, config.repository_access
    manager.create_article_repositories config.hub_organization, opts.authors, edition, batch: global.batch
    say hub.say 'The %s issue of %s is underway!' % [edition.month_formatted, periodical.name]
  end
end; end




=begin
if we want to use positional arguments:
arg_name '<edition> <login>[,<login>]*'

unless (edition_number = args.first) && (Editions::EditionNumberRx =~ edition_number)
  help_now! 'Missing required argument <edition> (volume and issue number of this edition, (e.g., 5.1))'
end
=end
