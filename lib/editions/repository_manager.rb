module Editions
class RepositoryManager
  # QUESTION make batch mode a field? read git_name, git_email and repository_access from config param?
  def initialize hub, git_name, git_email, repository_access = :public
    @hub = hub
    @git_name = git_name
    @git_email = git_email
    @repository_access = repository_access.to_sym
  end

  def clone_repository_root
    %(https://#{@hub.access_token}:x-oauth-basic@github.com/)
  end

  def submodule_repository_root
    @repository_access == :private ? 'git@github.com:' : 'https://github.com/'
  end

  def contributor_team org, options = {}
    unless (team = (@hub.org_teams org).find {|team| team.name.downcase == 'contributors' })
      team = create_contributor_team org, options if options[:auto_create]
    end
    team
  end

  def create_contributor_team org, options = {}
    @hub.create_team org, name: 'Contributors', permission: (options[:permission] || 'push')
  end

  def create_article_repositories org, authors, edition, options = {}
    prefix = (slug = edition.periodical.slug) ? %(#{slug}-) : nil
    options = options.merge prefix: prefix

    team = contributor_team org, auto_create: true

    article_repos = authors.map do |author|
      # FIXME handle case the repository already exists
      if (article_repo = create_article_repository org, author, edition, options)
        article_repo.last_commit_sha = seed_article_repository article_repo, edition, options
        @hub.add_team_member team.id, author
        @hub.add_team_repo team.id, article_repo.full_name
      end
      article_repo
    end.compact

    if (master_repo = create_master_repository org, edition, options.merge(prefix: prefix))
      seed_master_repository master_repo, article_repos, edition, options
      @hub.add_team_repo team.id, master_repo.full_name
    end
    ([master_repo] + article_repos).compact
  end

  def create_article_repository org, author, edition, options = {}
    author_resource = @hub.user author
    author_name = author_resource.name
    author_resource.initials = author_name.gsub(/(?:^|\s)([A-Z])[^\s]*/, '\1')
    repo_name = '%s%s-%s' % [options[:prefix], edition.month, author]
    repo_qname = [org, repo_name] * '/'
    repo_desc = '%s\'s %s article for %s' % [author_name, edition.month_formatted, edition.periodical.name]
    begin
      repo = @hub.repo repo_qname
      say_warning %(The repository #{repo_qname} for #{author_name} has already been created.)
      repo.author = author_resource
      return repo
    rescue; end
    return unless options[:batch] || (agree %(Create the repository #{repo_qname} for #{author_name}? [y/n] ))
    repo = @hub.create_repo repo_name,
      organization: org,
      homepage: edition.periodical.url,
      description: repo_desc,
      has_wiki: false,
      has_issues: false,
      has_downloads: false,
      private: (@repository_access == :private),
      auto_init: true
    repo.author = author_resource
    repo
  end

  def seed_article_repository repo, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    org = repo.organization.login
    templates_repo_qname = [org, [options[:prefix], 'templates'].compact.join] * '/'
    last_commit_sha = nil

    ::Dir.mktmpdir 'rugged-' do |clone_dir|
      repo_clone = try_try_again limit: 3, wait: 1, message: 'Repository not yet available. Retrying in 1s...' do
        # TODO perhaps only use the access token when calling push?
        if ::Rugged.features.include? :https
          ::Rugged::Repository.clone_at %(#{clone_repository_root}#{repo_qname}.git), clone_dir
        else
          %x(git clone #{clone_repository_root}#{repo_qname}.git #{clone_dir})
          ::Rugged::Repository.new clone_dir
        end
      end

      template_vars = {
        author_name: repo.author.name,
        author_email: repo.author.email,
        repository_name: repo.name,
        repository_desc: repo.description,
        repository_url: %(https://github.com/#{repo.full_name}),
        edition_month: edition.month,
        draft_deadline: edition.pub_date.strftime('%B 15, %Y')
      }

      # TODO move to a function
      # TODO might want to aggregate bios & headshots into a place where they are easier to locate
      author_suffix = %(-#{repo.author.login})
      past_bio_contents = unless (repos = (@hub.org_repos org, type: @repository_access).select {|candidate|
        candidate.name != repo_name && (candidate.name.end_with? author_suffix) && (contents? candidate.full_name, 'bio.adoc')
      }).empty?
        ::Base64.decode64 @hub.contents(repos.map(&:full_name).sort.last, path: 'bio.adoc').content
      end

      seed_files = {
        'README.adoc'        => (template_contents templates_repo_qname, 'author-readme.adoc', template_vars),
        %(#{repo_name}.adoc) => (template_contents templates_repo_qname, 'article-template.adoc', template_vars),
        'bio.adoc'           => (past_bio_contents || (template_contents templates_repo_qname, 'bio-template.adoc', template_vars))
      }

      index = repo_clone.index

      ::File.unlink(::File.join repo_clone.workdir, 'README.md')
      index.remove 'README.md'

      seed_files.each do |filename, contents|
        ::File.open(::File.join(repo_clone.workdir, filename), 'w') {|fd| fd.write contents }
        index.add path: filename, oid: (::Rugged::Blob.from_workdir repo_clone, filename), mode: 0100644
      end

      commit_tree = index.write_tree repo_clone
      index.write

      commit_author = { name: @git_name, email: @git_email, time: ::Time.now }

      ::Rugged::Commit.create repo_clone,
        author: commit_author,
        committer: commit_author,
        message: 'Add README, seed article and bio',
        parents: [repo_clone.head.target],
        tree: commit_tree,
        update_ref: 'HEAD'

      if ::Rugged.features.include? :https
        repo_clone.push 'origin', ['refs/heads/master']
      else
        ::Dir.chdir repo_clone.workdir do
          %x(git push origin master)
        end
      end
      last_commit_sha = repo_clone.head.target_id
    end
    last_commit_sha
  end

  def delete_article_repositories org, authors, edition, options = {}
    authors.each do |author|
      delete_article_repository org, author, edition, options
    end
  end

  def delete_article_repository org, author, edition, options = {}
    prefix = (slug = edition.periodical.slug) ? %(#{slug}-) : nil
    repo_name = '%s%s-%s' % [prefix, edition.month, author]
    repo_qname = [org, repo_name] * '/'
    unless @hub.repository? repo_qname
      say_warning %(The repository #{repo_qname} does not exist.)
      return
    end

    return unless options[:batch] || (agree %(Are you *absolutely* sure you want to delete the repository #{repo_qname}? [y/n] ))
    # NOTE If OAuth is used, 'delete_repo' scope is required
    # QUESTION should we remove the author from the contributor team?
    if @hub.delete_repo repo_qname
      say_ok %(Successfully deleted the repository #{repo_qname}.)
    else
      # NOTE this likely happens because the client isn't authenticated or doesn't have the delete_repo scope
      say_warning %(The repository #{repo_qname} could not be deleted.)
    end
  end

  def delete_all_article_repositories org, edition, options = {}
    previous_auto_paginate = @hub.auto_paginate
    @hub.auto_paginate = true
    root_name = [edition.periodical.slug, edition.month].compact * '-'
    (@hub.org_repos org, type: @repository_access).select {|repo| repo.name.start_with? root_name }.each do |repo|
      repo_qname = repo.full_name
      next unless options[:batch] || (agree %(Are you *absolutely* sure you want to delete the repository #{repo_qname}? [y/n] ))
      # NOTE If OAuth is used, 'delete_repo' scope is required
      # QUESTION should we remove the author from the contributor team?
      if @hub.delete_repo repo_qname
        say_ok %(Successfully deleted the repository #{repo_qname}.)
      else
        # NOTE this likely happens because the client isn't authenticated or doesn't have the delete_repo scope
        say_warning %(The repository #{repo_qname} could not be deleted.)
      end
    end
  ensure
    @hub.auto_paginate = previous_auto_paginate
  end

  def create_master_repository org, edition, options = {}
    repo_name = [options[:prefix], edition.month].join
    repo_qname = [org, repo_name] * '/'
    repo_desc = '%s issue of %s' % [edition.month_formatted, edition.periodical.name]

    begin
      repo = @hub.repo repo_qname
      say_warning %(The master repository #{repo_qname} has already been created.)
      return repo
    rescue; end
    return unless options[:batch] || (agree %(Create the master repository #{repo_qname}? [y/n] ))

    @hub.create_repo repo_name,
      organization: org,
      homepage: edition.periodical.url,
      description: repo_desc,
      has_wiki: false,
      has_issues: false,
      has_downloads: false,
      private: (@repository_access == :private),
      auto_init: true
  end

  #--
  # TODO stub publisher's letter
  # NOTE update submodules using
  # $ git submodule foreach git pull origin master
  def seed_master_repository repo, article_repos, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    master_doc_filename = %(#{repo_name}.adoc)
    ::Dir.mktmpdir 'rugged-' do |clone_dir|
      repo_clone = try_try_again limit: 3, wait: 1, message: 'Repository not yet available. Retrying in 1s...' do
        # TODO perhaps only use the access token when calling push?
        if ::Rugged.features.include? :https
          ::Rugged::Repository.clone_at %(#{clone_repository_root}#{repo_qname}.git), clone_dir
        else
          %x(git clone #{clone_repository_root}#{repo_qname}.git #{clone_dir})
          ::Rugged::Repository.new clone_dir
        end
      end

      author_names = article_repos.map {|r| r.author.name }

      master_doc_content = <<-EOS.chomp
= #{edition.periodical.name} - #{edition.month_formatted}
#{author_names * '; '}
v#{edition.number}, #{edition.pub_date.xmlschema}
:doctype: book
:producer: #{edition.periodical.producer}
      EOS

      index = repo_clone.index

      article_repos.each do |article_repo|
        article_repo_name = article_repo.name
        article_repo_qname = article_repo.full_name
        author_initials = article_repo.author.initials
        master_doc_content = <<-EOS.chomp
#{master_doc_content}

:codedir: #{article_repo_name}/code
:imagesdir: #{article_repo_name}/images
:listing-caption: Listing #{author_initials} -
:figure-caption: Figure #{author_initials} -
:idprefix: #{author_initials.downcase}_
include::#{article_repo_name}/#{article_repo_name}.adoc[]
        EOS

        ::Refined::Submodule.add repo_clone,
          article_repo_name,
          %(#{submodule_repository_root}#{article_repo_qname}.git),
          article_repo.last_commit_sha,
          index: index
      end

      ::File.open(::File.join(repo_clone.workdir, master_doc_filename), 'w') {|fd| fd.write master_doc_content }
      index.add path: master_doc_filename, oid: (::Rugged::Blob.from_workdir repo_clone, master_doc_filename), mode: 0100644

      ::File.unlink(::File.join repo_clone.workdir, 'README.md')
      index.remove 'README.md'

      commit_tree = index.write_tree repo_clone
      index.write

      commit_author = { name: @git_name, email: @git_email, time: ::Time.now }
      ::Rugged::Commit.create repo_clone,
        author: commit_author,
        committer: commit_author,
        message: 'Seed master document and link article repositories as submodules',
        parents: [repo_clone.head.target],
        tree: commit_tree,
        update_ref: 'HEAD'

      if ::Rugged.features.include? :https
        repo_clone.push 'origin', ['refs/heads/master']
      else
        ::Dir.chdir repo_clone.workdir do
          %x(git push origin master)
        end
      end
    end
  end

  # QUESTION should we move template_contents to an Editions::TemplateManager class?
  def template_contents repo, path, vars = {}
    content = begin
      ::Base64.decode64 @hub.contents(repo, path: path).content
    rescue ::Octokit::NotFound
      ::File.read ::File.join(DATADIR, 'templates', path)
    end

    unless vars.nil_or_empty?
      # TODO move regexp to constant
      content = content.gsub(/\{template_(.*?)\}/) { vars[$1.to_sym] }
    end

    content
  end

  def contents? repo, path
    @hub.contents repo, path: path
    true
  rescue ::Octokit::NotFound
    false
  end

  # TODO move me to a utility mixin
  def try_try_again options = {}
    attempts = 0
    retry_limit = options[:limit] || 3
    retry_wait = options[:wait] || 1
    retry_message = options[:message] || 'Retrying...'
    begin
      yield
    rescue => e
      if retry_count < retry_limit
        attempts += 1
        say_warning retry_message
        sleep retry_wait if retry_wait > 0
        retry
      else
        raise e
      end
    end
  end
end
end
