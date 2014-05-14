desc 'Initialize the repositories for an edition'
command :init do |cmd|; cmd.instance_eval do
  flag :e, :edition,
    arg_name: '<edition>',
    desc: 'The volume and issue number of this edition (e.g., 5.1)',
    required: true,
    # Editions::EditionNumber parses volume and issue number parts into an Array
    type: Editions::EditionNumber,
    must_match: Editions::EditionNumberRx

  flag :p, :pubdate,
    arg_name: '<date>',
    desc: %(The publication date of this edition (e.g., #{current_month = Time.now.strftime '%Y-%m'})),
    required: true,
    must_match: Editions::EditionDateRx

  flag :a, :authors,
    arg_name: '<login>[,<login>]*',
    desc: 'A comma-separated list of usernames of the contributing authors (will prompt if not specified)',
    type: Array

  flag :t, :title,
    arg_name: '<title>',
    desc: 'The title of this edition'

  config_required

  action do |global, opts, args, config = global.config|
    if opts.authors.nil_or_empty?
      opts.authors = ask 'Enter the username of each author (comma-separated): ', ->(s) { s.split /(?:\s*,\s*|\s+)/ }
      help_now! 'You must specify at least one username.' if opts.authors.empty?
    end

    hub = Editions::Hub.connect config, %w(repo)
    edition = Editions::Edition.new opts.edition, nil, opts.pubdate, (publication = Editions::Publication.from config), opts.title
    manager = Editions::RepositoryManager.new hub, config.git_name, config.git_email, config.repository_access
    manager.create_repositories_for_edition config.hub_organization, edition, opts.authors, batch: global.batch
    say hub.say 'The %s edition of %s is underway!' % [edition.month_formatted, publication.name]
  end
end; end

=begin
if we want to use positional arguments:
arg_name '<edition> <login>[,<login>]*'

unless (edition_number = args.first) && (Editions::EditionNumberRx =~ edition_number)
  help_now! 'Missing required argument <edition> (volume and issue number of this edition, (e.g., 5.1))'
end
=end
