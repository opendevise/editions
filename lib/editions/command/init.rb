desc 'Create and seed the article repositories for an edition'
command :init do |cmd|; cmd.instance_eval do
  flag :p, :period,
    arg_name: '<date>',
    desc: %(The period of the issue (e.g., #{Time.now.strftime '%Y-%m'})),
    default_value: (Time.now.strftime '%Y-%m')

  flag :a, :authors,
    arg_name: '<login>[,<login>]*',
    desc: 'A comma-separated list of usernames of the contributing authors',
    type: Array,
    required: true

  action do |global, opts, args|
    config = global.config
    exit_now! color(%(error: #{global.profile || 'global'} profile does not exist. Please run `config' to configure your environment.), :red) unless config
    #require 'octokit' unless defined? Octokit::Client

    # TODO we could still connect using netrc
    gh = Octokit::Client.new access_token: config.access_token

    period = opts.period
    # TODO make this a utility method
    period_date = DateTime.parse %(#{period}-01)

    # TODO prompt if no authors are given
    opts.authors.each do |username|
      # TODO complain if username is invalid
      author_resource = gh.user username
      author_name = author_resource.name
      repo_name = '%s%s-%s' % [(global.profile ? %(#{global.profile}-) : ''), period, username]
      repo_qname = '%s/%s' % [config.org, repo_name]
      repo_desc = '%s\'s %s article for %s' % [author_name, (period_date.strftime '%B %Y'), config.title]
      repo = begin
        gh.repo repo_qname
        say %(The repository #{repo_qname} for #{author_name} has already been created. Skipping.)
        next
      rescue; end
      next unless global.y || (agree %(Create the repository #{repo_qname} for #{author_name}? ))
      repo = gh.create_repo repo_name,
        organization: config.org,
        homepage: config.homepage,
        description: repo_desc,
        has_wiki: false,
        has_issues: false,
        has_downloads: false,
        private: config.private,
        auto_init: true
      #gh.add_collaborator repo_qname, username
      # TODO include information about how to use Asciidoctor and Asciidoctor.js Live Preview
      readme_content = <<-END.chomp
= #{repo_name}

#{repo_desc}
      END

      article_content = <<-END.chomp
= Article Title
#{author_name}
:imagesdir: images

[abstract]
--
Write the abstract here.
--

== Section Title

Write me.
      END

      readme_resource = gh.contents repo_qname, :path => 'README.md'
      # TODO delete only if readme is found
      gh.delete_contents repo_qname, 'README.md', 'Removing Markdown README', readme_resource.sha
      gh.create_contents repo_qname, 'README.adoc', 'Adding AsciiDoc README', readme_content
      gh.create_contents repo_qname, %(#{repo_name}.adoc), 'Seeding article', article_content
      # TODO seed the images and code directories (probably need to create a sample file in each)
    end

    say gh.say 'The %s issue of %s is underway!' % [(period_date.strftime '%B %Y'), config.title]
  end
end; end
