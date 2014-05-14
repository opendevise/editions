module Editions
class RepositoryManager
  # TODO make this logic more robust
  InitialsRx = /(?:^|\s)(?<initial>[A-Z])[^\s]*/

  # QUESTION make batch mode a field? read git_name, git_email and repository_access from config param?
  def initialize hub, git_name, git_email, repository_access = :public
    @hub = hub
    @git_name = git_name
    @git_email = git_email
    @repository_access = repository_access.to_sym
  end

  def clone_repository_root
    %(https://#{@hub.access_token}:x-oauth-basic@#{@hub.host}/)
  end

  def build_clone_url repo_qname
    %(#{clone_repository_root}#{repo_qname}.git)
  end

  def inject_with_auth repo_url
    repo_url.sub 'https://', %(https://#{@hub.access_token}:x-oauth-basic@)
  end

  def submodule_repository_root
    @repository_access == :private ? %(git@:#{@hub.host}) : %(https://#{@hub.host}/)
  end

  def contributor_team org, options = {}
    previous_auto_paginate = @hub.auto_paginate
    @hub.auto_paginate = true
    team_name_match = (options[:name] ||= 'Authors and Editors').downcase
    unless (team = (@hub.org_teams org).find {|team| team.name.downcase == team_name_match })
      team = create_contributor_team org, options if options[:auto_create]
    end
    team
  ensure
    @hub.auto_paginate = previous_auto_paginate
  end

  # IMPORTANT When you grant push or admin access to a team, all members will receive e-mail notifications
  # that they have been granted access unless a member has notifications explicitly disabled in their settings.
  def create_contributor_team org, options = {}
    @hub.create_team org, name: options[:name], permission: (options[:permission] || 'pull')
  end

  # Called by the init command to setup the git repositories for the specified edition.
  #
  # Creates a repository for each author / article and another repository for the spine
  # document and common assets.
  def create_repositories_for_edition org, edition, authors = [], options = {}
    author_editor_team = contributor_team org, auto_create: true
    edition_team = contributor_team org, name: edition.handle, permission: 'push', auto_create: true

    article_repos = authors.map do |author|
      # FIXME handle case the repository already exists
      if (article_repo = create_article_repository org, edition, author, options)
        article_repo.last_commit_sha = seed_article_repository article_repo, edition, options
        @hub.add_team_member author_editor_team.id, author
        @hub.add_team_repo author_editor_team.id, article_repo.full_name
        @hub.add_team_member edition_team.id, author
        @hub.add_team_repo edition_team.id, article_repo.full_name
      end
      article_repo
    end.compact

    if (master_repo = create_master_repository org, edition, options)
      seed_master_repository master_repo, article_repos, edition, options
      @hub.add_team_repo author_editor_team.id, master_repo.full_name
      @hub.add_team_repo edition_team.id, master_repo.full_name
    end
    ([master_repo] + article_repos).compact
  end

  def create_article_repository org, edition, author, options = {}
    author_resource = @hub.user author
    author_name = author_resource.name
    author_resource.initials = author_name.gsub InitialsRx, '\k<initial>'
    repo_name = [edition.handle, author] * '-'
    repo_qname = [org, repo_name] * '/'
    repo_desc = '%s\'s %s article for %s' % [author_name, edition.month_formatted, edition.periodical.name]
    begin
      repo = @hub.repo repo_qname
      say_warning %(The repository #{repo_qname} for #{author_name} already exists.)
      repo.author = author_resource
      return repo
    rescue; end
    return unless options[:batch] || (agree %(Create the #{colorize @repository_access.to_s, :underline} repository #{colorize repo_qname, :bold} for #{colorize author_name, :bold}? [y/n] ))
    repo = @hub.create_repo repo_name,
      organization: org,
      homepage: edition.periodical.url,
      description: repo_desc,
      has_wiki: false,
      has_issues: false,
      has_downloads: false,
      private: (@repository_access == :private),
      auto_init: true
    say_ok %(Successfully created the repository #{repo_qname})
    repo.author = author_resource
    repo
  end

  def seed_article_repository repo, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    org = repo.organization.login
    assets_repo_qname = [org, [edition.periodical.handle, 'assets'].compact * '-'] * '/'
    docs_repo_qname = [org, [edition.periodical.handle, 'docs'].compact * '-'] * '/'
    last_commit_sha = nil

    ::Dir.mktmpdir 'rugged-' do |clone_dir|
      repo_clone = try_try_again limit: 3, wait: 1, message: 'Repository not yet available. Retrying in 1s...' do
        # TODO perhaps only use the access token when calling push?
        # TODO gracefully handle failure
        ::Refined::Repository.clone_at (build_clone_url repo_qname), clone_dir
      end

      # TODO move hunt for an author uri / email to an Octokit mixin
      author_username = repo.author.login
      if (author_email = repo.author.email).nil_or_empty?
        if (author_uri = repo.author.blog).nil_or_empty?
          author_uri = %(https://#{@hub.host}/#{author_username})
        else
          author_uri = %(http://#{author_uri}) unless author_uri.start_with? 'http'
        end
        author_email = %(#{author_uri}[@#{author_username}])
      else
        author_uri = nil
      end

      template_vars = {
        'author-name' => repo.author.name,
        'author-email' => author_email,
        'author-uri' => author_uri,
        'author-username' => author_username,
        'repository-name' => repo.name,
        'repository-desc' => repo.description,
        'repository-url' => %(https://#{@hub.host}/#{repo.full_name}),
        'edition-number' => edition.number,
        'edition-month' => edition.month,
        'draft-deadline' => (edition.pub_date.strftime '%B 15, %Y')
      }

      profile_assets = ['bio.adoc', 'avatar.jpg', 'headshot.jpg'].map do |asset_name|
        asset_qname = %(#{author_username}-#{asset_name})
        if contents? assets_repo_qname, (asset_path = %(profiles/#{author_username}/#{asset_name}))
          [asset_qname, (::Base64.decode64 (@hub.contents assets_repo_qname, path: asset_path).content)]
        elsif asset_name == 'bio.adoc'
          [asset_qname, (template_contents assets_repo_qname, 'seed-bio.adoc', template_vars)]
        else
          [asset_qname, nil]
        end
      end.to_h

      seed_files = {
        'README.adoc'        => (template_contents assets_repo_qname, 'article-readme.adoc', template_vars),
        'article.adoc'       => (template_contents assets_repo_qname, 'seed-article.adoc', template_vars),
        # TODO is there an API for managing gitignore we can use?
        '.gitignore'         => %w(/*.html).join("\n"),
        'code/.gitkeep'      => '',
        'images/.gitkeep'    => ''
      }.merge profile_assets

      index = repo_clone.index

      seed_files.each do |filename, contents|
        if contents
          # TODO make a helper for creating files & adding to git index
          ::FileUtils.mkdir_p (::File.join repo_clone.workdir, (::File.dirname filename)) if filename.include? '/'
          ::File.open((::File.join repo_clone.workdir, filename), 'w') {|fd| fd.write contents }
          index.add path: filename, oid: (::Rugged::Blob.from_workdir repo_clone, filename), mode: 0100644
        end
      end

      ::File.unlink (::File.join repo_clone.workdir, 'README.md')
      index.remove 'README.md'

      begin
        ::Refined::Submodule.add repo_clone,
          'docs',
          %(#{submodule_repository_root}#{docs_repo_qname}.git),
          # TODO cache this info
          (@hub.branch docs_repo_qname, 'master').commit.sha,
          index: index
      rescue
        say_warning %(Could not locate the docs repository: #{docs_repo_qname}. Creating article repository without a docs submodule.)
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

      ::Refined::Repository.push repo_clone

      # NOTE backwards compatibility hack for Rugged 0.19.0
      unless (last_commit_sha = repo_clone.head.target).is_a? ::String
        last_commit_sha = repo_clone.head.target_id
      end
    end
    last_commit_sha
  end

  def delete_article_repositories org, authors, edition, options = {}
    authors.each do |author|
      delete_article_repository org, author, edition, options
    end
  end

  def delete_article_repository org, author, edition, options = {}
    repo_name = [edition.handle, author] * '-'
    repo_qname = [org, repo_name] * '/'
    unless @hub.repository? repo_qname
      say_warning %(The repository #{repo_qname} does not exist.)
      return
    end

    return unless options[:batch] || (agree %(Are you *#{colorize 'absolutely', :underline}* sure you want to delete the repository #{colorize repo_qname, :bold}? [y/n] ))
    # NOTE If OAuth is used, 'delete_repo' scope is required
    # QUESTION should we remove the author from the contributor team?
    if @hub.delete_repo repo_qname
      say_ok %(Successfully deleted the repository #{repo_qname})
    else
      # NOTE this likely happens because the client isn't authenticated or doesn't have the delete_repo scope
      say_warning %(The repository #{repo_qname} could not be deleted)
    end
  end

  def delete_repositories_for_edition org, edition, options = {}
    previous_auto_paginate = @hub.auto_paginate
    @hub.auto_paginate = true
    root_name = edition.handle
    (@hub.org_repos org, type: @repository_access).select {|repo| repo.name.start_with? root_name }.each do |repo|
      repo_qname = repo.full_name
      next unless options[:batch] || (agree %(Are you *#{colorize 'absolutely', :underline}* sure you want to delete the repository #{colorize repo_qname, :bold}? [y/n] ))
      # NOTE If OAuth is used, 'delete_repo' scope is required
      # QUESTION should we remove the author from the contributor team?
      if @hub.delete_repo repo_qname
        say_ok %(Successfully deleted the repository #{repo_qname})
      else
        # NOTE this likely happens because the client isn't authenticated or doesn't have the delete_repo scope
        say_warning %(The repository #{repo_qname} could not be deleted)
      end
    end
    if (edition_team = (contributor_team org, name: root_name))
      @hub.delete_team edition_team.id
    end
  ensure
    @hub.auto_paginate = previous_auto_paginate
  end

  def create_master_repository org, edition, options = {}
    repo_name = edition.handle
    repo_qname = [org, repo_name] * '/'
    repo_desc = 'The %s Edition of %s' % [edition.month_formatted, edition.periodical.name]

    begin
      repo = @hub.repo repo_qname
      say_warning %(The master repository #{repo_qname} already exists)
      return repo
    rescue; end
    return unless options[:batch] || (agree %(Create the #{colorize @repository_access.to_s, :underline} master repository #{colorize repo_qname, :bold}? [y/n] ))

    repo = @hub.create_repo repo_name,
      organization: org,
      homepage: edition.periodical.url,
      description: repo_desc,
      has_wiki: false,
      has_issues: false,
      has_downloads: false,
      private: (@repository_access == :private),
      auto_init: true
    say_ok %(Successfully created the repository #{repo_qname})
    repo
  end

  #--
  # TODO stub publisher's letter
  # NOTE update submodules using
  # $ git submodule foreach git pull origin master
  def seed_master_repository repo, article_repos, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    assets_repo_qname = [repo.organization.login, [edition.periodical.handle, 'assets'].compact * '-'] * '/'
    spine_doc_filename = %(#{repo_name}.adoc)
    spine_config_filename = 'config.yml'
    ::Dir.mktmpdir 'rugged-' do |clone_dir|
      repo_clone = try_try_again limit: 3, wait: 1, message: 'Repository not yet available. Retrying in 1s...' do
        # TODO perhaps only use the access token when calling push?
        ::Refined::Repository.clone_at (build_clone_url repo_qname), clone_dir
      end

      author_names = article_repos.map {|r| r.author.name }

      # TODO use template vars instead of interpolation (makes it easier to extract)
      spine_doc_content = <<-EOS.chomp
= #{edition.full_title}
#{author_names * '; '}
v#{edition.number}, #{edition.pub_date.strftime '%Y-%m-%d'}
:doctype: book
:publisher: #{edition.periodical.publisher}
:app-name: #{edition.periodical.name}
//:subject: TODO
//:keywords: TODO
:description: #{edition.description.sub ': ', ": +\n"}
:pub-handle: #{edition.periodical.handle}
:pub-date: #{edition.year_month}
:pub-url: #{edition.periodical.url}
:edition: {revnumber}
:edition-handle: #{edition.handle}
:volume: #{edition.volume}
:issue: #{edition.issue}
:listing-caption: Listing
:codedir: code
:imagesdir: images
ifdef::backend-pdf,asciidoctor-pdf[]
:leveloffset: 1
:toc:
:toclevels: 1
:toc-title: Contents
:source-highlighter: pygments
:pygments-style: bw
endif::[]
ifdef::env-github[:buildfor-editor:]
//:front-cover-image: image:jacket/front-cover.jpg[Cover,1050,1600]
//:back-cover-image: image:jacket/back-cover.jpg[Cover,1050,1600]

ifdef::buildfor-editor[]
:username: publisher
include::publishers-letter.adoc[]
endif::[]
      EOS

      spine_config = {
        'edition' => edition.number,
        'publicationDate' => edition.year_month,
        'buildDir' => 'build',
        'articles' => []
      }

      index = repo_clone.index

      article_repos.each do |article_repo|
        article_repo_name = article_repo.name
        article_repo_qname = article_repo.full_name
        author_username = article_repo.author.login
        article_repo_vname = article_repo_name.gsub(edition.handle, '{edition-handle}').gsub(author_username, '{username}')
        author_initials = article_repo.author.initials.downcase
        spine_doc_content = <<-EOS.chomp
#{spine_doc_content}

ifdef::buildfor-editor,buildfor-#{author_username}[]
:username: #{author_username}
:idprefix: #{author_initials}_
:articledir: #{article_repo_vname}
:imagesdir: #{article_repo_name}/images
include::{articledir}/article.adoc[]
endif::[]
        EOS

        spine_config['articles'] << {
          'username' => author_username,
          'localDir' => article_repo_name,
          'repository' => {
            'clone_url' => article_repo.clone_url,
            'ssh_url' => article_repo.ssh_url
          }
        }

        #::Refined::Submodule.add repo_clone,
        #  article_repo_name,
        #  %(#{submodule_repository_root}#{article_repo_qname}.git),
        #  article_repo.last_commit_sha,
        #  index: index
      end

      # FIXME reset images after parse so this assignment isn't required
      spine_doc_content = <<-EOS.chomp
#{spine_doc_content}

// FIXME converters should restore attributes after parsing/rendering
:imagesdir: images
      EOS

      template_vars = {
        'publisher-name' => edition.publisher,
        'publication-name' => edition.periodical.name,
        'publication-url' => edition.periodical.url,
        'edition-month' => edition.month_formatted
      }

      publisher_profile_assets = ['avatar.jpg', 'headshot.jpg'].map do |asset_name|
        asset_qname = %(publisher-#{asset_name})
        if contents? assets_repo_qname, (asset_path = %(profiles/publisher/#{asset_name}))
          [asset_qname, (::Base64.decode64 (@hub.contents assets_repo_qname, path: asset_path).content)]
        else
          [asset_qname, nil]
        end
      end.to_h

      insert_assets = begin
        (@hub.contents assets_repo_qname, path: 'inserts').map do |asset|
          [%(images/inserts/#{asset.name}), (::Base64.decode64 (@hub.contents assets_repo_qname, path: asset.path).content)]
        end.to_h
      rescue ::Octokit::NotFound
        { 'images/inserts/.gitkeep' => '' }
      end

      seed_files = {
        spine_doc_filename        => spine_doc_content,
        spine_config_filename     => spine_config.to_yaml.sub(/\A---\n/, ''),
        # TODO is there an API for managing gitignore we can use?
        '.gitignore'              => %W(/build/ /#{repo_name}-*/ /images/avatars/ /images/headshots/ /*.html /*.pdf*).join("\n"),
        'publishers-letter.adoc'  => (template_contents assets_repo_qname, 'seed-publishers-letter.adoc', template_vars),
        'images/jacket/.gitkeep'  => ''
      }.merge(publisher_profile_assets).merge(insert_assets)

      seed_files.each do |filename, contents|
        if contents
          # TODO make a helper for creating files & adding to git index
          ::FileUtils.mkdir_p (::File.join repo_clone.workdir, (::File.dirname filename)) if filename.include? '/'
          ::File.open((::File.join repo_clone.workdir, filename), 'w') {|fd| fd.write contents }
          index.add path: filename, oid: (::Rugged::Blob.from_workdir repo_clone, filename), mode: 0100644
        end
      end

      # TODO move to a method
      begin
        assets_repo = [repo.organization.login, [edition.periodical.handle, 'assets'].compact * '-'] * '/'

        epub3_css_filename = ::File.join 'styles', 'epub3.css'
        epub3_css_content = ::Base64.decode64 (@hub.contents assets_repo, path: epub3_css_filename).content

        epub3_css3_filename = ::File.join 'styles', 'epub3-css3-only.css'
        epub3_css3_content = ::Base64.decode64 (@hub.contents assets_repo, path: epub3_css3_filename).content

        ::Dir.mkdir (::File.join repo_clone.workdir, 'styles')

        ::File.open((::File.join repo_clone.workdir, epub3_css_filename), 'w') {|fd| fd.write epub3_css_content }
        index.add path: epub3_css_filename, oid: (::Rugged::Blob.from_workdir repo_clone, epub3_css_filename), mode: 0100644

        ::File.open((::File.join repo_clone.workdir, epub3_css3_filename), 'w') {|fd| fd.write epub3_css3_content }
        index.add path: epub3_css3_filename, oid: (::Rugged::Blob.from_workdir repo_clone, epub3_css3_filename), mode: 0100644
      rescue ::Octokit::NotFound
        # ignore
      end

      ::File.unlink (::File.join repo_clone.workdir, 'README.md')
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

      ::Refined::Repository.push repo_clone
    end
  end

  # QUESTION should we move template_contents to an Editions::TemplateManager class?
  # TODO create a method for retrieving raw contents (w/o substitutions)
  def template_contents repo, path, vars = nil
    content = begin
      ::Base64.decode64 (@hub.contents repo, path: (::File.join 'templates', path)).content
    rescue ::Octokit::NotFound
      ::File.read (::File.join DATADIR, 'templates', path)
    end

    unless vars.nil_or_empty?
      # TODO move regexp to constant
      content = content.gsub(/\{template-(.*?)\}/) { vars[$1] }
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
      if attempts < retry_limit
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
