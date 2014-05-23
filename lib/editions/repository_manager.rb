module Editions
# TODO reorder methods into a more logical order
class RepositoryManager
  # TODO make the initials logic more robust
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

  # FIXME need to be able to override access-level
  def submodule_repository_root
    #@repository_access == :private ? %(git@:#{@hub.host}) : %(https://#{@hub.host}/)
    %(https://#{@hub.host})
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

    article_repos = authors.map{|author|
      if (article_repo = create_article_repository org, edition, author, options)
        seed_article_repository article_repo, edition, options unless article_repo.seeded
        # Add author to authors & editors team (read-only)
        @hub.add_team_member author_editor_team.id, author
        @hub.add_team_repo author_editor_team.id, article_repo.full_name
        # Add author to team for this edition (read-write)
        @hub.add_team_member edition_team.id, author
        @hub.add_team_repo edition_team.id, article_repo.full_name
      end
      article_repo
    }

    if (spine_repo = create_spine_repository org, edition, options)
      if spine_repo.seeded
        update_spine_repository spine_repo, article_repos, edition, options
      else
        seed_spine_repository spine_repo, article_repos, edition, options
      end
      @hub.add_team_repo author_editor_team.id, spine_repo.full_name
      @hub.add_team_repo edition_team.id, spine_repo.full_name
    end
    ([spine_repo] + article_repos).compact
  end

  def create_article_repository org, edition, author, options = {}
    author_resource = @hub.user author
    author_name = author_resource.name
    author_resource.initials = author_name.gsub InitialsRx, '\k<initial>'
    repo_name = [edition.handle, author] * '-'
    repo_qname = [org, repo_name] * '/'
    repo_desc = '%s\'s %s article for %s' % [author_name, edition.month_formatted, edition.publication.name]
    begin
      repo = @hub.repo repo_qname
      say_warning %(The repository #{repo_qname} for #{author_name} already exists.)
      repo.author = author_resource
      repo.seeded = true
      return repo
    rescue; end
    return unless options[:batch] || (agree %(Create the #{colorize @repository_access.to_s, :underline} repository #{colorize repo_qname, :bold} for #{colorize author_name, :bold}? [y/n] ))
    repo = @hub.create_repo repo_name,
      organization: org,
      homepage: edition.publication.url,
      description: repo_desc,
      has_wiki: false,
      has_issues: false,
      has_downloads: false,
      private: (@repository_access == :private),
      auto_init: true
    say_ok %(Successfully created the repository #{repo_qname})
    repo.author = author_resource
    repo.seeded = false
    repo
  end

  def seed_article_repository repo, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    org = repo.organization.login
    assets_repo_qname = [org, [edition.publication.handle, 'assets'].compact * '-'] * '/'
    docs_repo_qname = [org, [edition.publication.handle, 'docs'].compact * '-'] * '/'
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

      profile_assets = ['bio.adoc', 'avatar.jpg', 'headshot.jpg'].map {|asset_name|
        asset_qname = %(#{author_username}-#{asset_name})
        if asset_name == 'bio.adoc'
          [asset_qname, (template_content assets_repo_qname, 'seed-bio.adoc', template_vars)]
        elsif asset? assets_repo_qname, (asset_path = %(profiles/#{author_username}/#{asset_name}))
          [asset_qname, (asset_content assets_repo_qname, asset_path)]
        else
          [asset_qname, nil]
        end
      }.to_h

      seed_files = {
        'README.adoc'        => (template_content assets_repo_qname, 'article-readme.adoc', template_vars),
        'article.adoc'       => (template_content assets_repo_qname, 'seed-article.adoc', template_vars),
        # TODO is there an API for managing gitignore we can use?
        '.gitignore'         => %w(/*.html).join("\n"),
        'code/.gitkeep'      => '',
        'images/.gitkeep'    => ''
      }.merge profile_assets

      index = repo_clone.index

      # TODO make a helper for creating files & adding to git index
      seed_files.each do |filename, contents|
        if contents
          ::FileUtils.mkdir_p (::File.join repo_clone.workdir, (::File.dirname filename)) if filename.include? '/'
          ::File.open((::File.join repo_clone.workdir, filename), 'wb') {|fd| fd.write contents }
          index.add path: filename, oid: (::Rugged::Blob.from_workdir repo_clone, filename), mode: 0100644
        end
      end

      ::File.unlink (::File.join repo_clone.workdir, 'README.md')
      index.remove 'README.md'

      begin
        ::Refined::Submodule.add repo_clone,
          'docs',
          %(#{submodule_repository_root}#{docs_repo_qname}.git),
          # TODO cache the last commit sha of the docs repository
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
      repo.seeded = true    
    end
    last_commit_sha
  end

  def delete_article_repositories org, authors, edition, options = {}
    authors.each do |author|
      delete_article_repository org, author, edition, options
    end
  end

  # TODO remove repository from config.yml in spine repository
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

  def create_spine_repository org, edition, options = {}
    repo_name = edition.handle
    repo_qname = [org, repo_name] * '/'
    repo_desc = 'The %s Edition of %s' % [edition.month_formatted, edition.publication.name]

    begin
      repo = @hub.repo repo_qname
      say_warning %(The spine repository #{repo_qname} already exists.)
      repo.seeded = true
      return repo
    rescue; end
    return unless options[:batch] || (agree %(Create the #{colorize @repository_access.to_s, :underline} spine repository #{colorize repo_qname, :bold}? [y/n] ))

    repo = @hub.create_repo repo_name,
      organization: org,
      homepage: edition.publication.url,
      description: repo_desc,
      has_wiki: false,
      has_issues: false,
      has_downloads: false,
      private: (@repository_access == :private),
      auto_init: true
    say_ok %(Successfully created the repository #{repo_qname})
    repo.seeded = false
    repo
  end

  # Update the configuration file in the spine repository to include only the
  # provided list of article repositories.
  def update_spine_repository repo, article_repos, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    spine_doc_filename = %(#{repo_name}.adoc)
    spine_config_filename = 'config.yml'
    ::Dir.mktmpdir 'rugged-' do |clone_dir|
      repo_clone = try_try_again limit: 3, wait: 1, message: 'Repository not yet available. Retrying in 1s...' do
        # TODO perhaps only use the access token when calling push?
        ::Refined::Repository.clone_at (build_clone_url repo_qname), clone_dir
      end

      spine_config = {
        'edition_number' => edition.number,
        'edition_handle' => edition.handle,
        'edition_pub_date' => edition.year_month,
        'build_dir' => 'build',
        'articles' => article_repos.map {|article_repo|
          {
            'username' => article_repo.author.login,
            'local_dir' => article_repo.name,
            'repository' => {
              'clone_url' => article_repo.clone_url,
              'ssh_url' => article_repo.ssh_url
            }
          }
        }
      }

      spine_doc_content = [(::File.read (::File.join repo_clone.workdir, spine_doc_filename))
          .gsub(/^ifdef::buildfor-editor,buildfor-.*/m, '').rstrip]
          .concat(article_repos.map {|article_repo|
            author = article_repo.author
            article_repo_vname = article_repo.name
                .gsub(edition.handle, '{edition-handle}')
                .gsub(author.login, '{username}')
            %(ifdef::buildfor-editor,buildfor-#{author.login}[]
:username: #{author.login}
:idprefix: #{author.initials.downcase}_
:articledir: #{article_repo_vname}
:imagesdir: #{article_repo.name}/images
include::{articledir}/article.adoc[]
endif::[])
      }) * "\n\n"

      seed_files = {
        spine_doc_filename => spine_doc_content,
        spine_config_filename => spine_config.to_yaml.sub(/\A---\n/, '')
      }

      index = repo_clone.index

      # FIXME make a helper for creating files & adding to git index
      seed_files.each do |filename, contents|
        if contents
          ::FileUtils.mkdir_p (::File.join repo_clone.workdir, (::File.dirname filename)) if filename.include? '/'
          ::File.open((::File.join repo_clone.workdir, filename), 'wb') {|fd| fd.write contents }
          index.add path: filename, oid: (::Rugged::Blob.from_workdir repo_clone, filename), mode: 0100644
        end
      end

      commit_tree = index.write_tree repo_clone
      index.write

      commit_author = { name: @git_name, email: @git_email, time: ::Time.now }
      ::Rugged::Commit.create repo_clone,
        author: commit_author,
        committer: commit_author,
        message: 'Update spine document and configuration file',
        parents: [repo_clone.head.target],
        tree: commit_tree,
        update_ref: 'HEAD'

      ::Refined::Repository.push repo_clone
    end
  end

  def seed_spine_repository repo, article_repos, edition, options = {}
    repo_name = repo.name
    repo_qname = repo.full_name
    assets_repo_qname = [repo.organization.login, [edition.publication.handle, 'assets'].compact * '-'] * '/'
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
:publisher: #{edition.publication.publisher}
:app-name: #{edition.publication.name}
//:subject: Subject 1, Subject 2, ...
:description: #{edition.description.sub ': ', ": +\n"}
:pub-handle: #{edition.publication.handle}
:pub-date: #{edition.year_month}
:pub-url: #{edition.publication.url}
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
        'edition_number' => edition.number,
        'edition_handle' => edition.handle,
        'edition_pub_date' => edition.year_month,
        'build_dir' => 'build',
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
          'local_dir' => article_repo_name,
          'repository' => {
            'clone_url' => article_repo.clone_url,
            'ssh_url' => article_repo.ssh_url
          }
        }
      end

      template_vars = {
        'publisher-name' => edition.publisher,
        'publication-name' => edition.publication.name,
        'publication-url' => edition.publication.url,
        'edition-month' => edition.month_formatted
      }

      publisher_profile_assets = ['avatar.jpg', 'headshot.jpg'].map {|asset_name|
        asset_qname = %(publisher-#{asset_name})
        if asset? assets_repo_qname, (asset_path = %(profiles/publisher/#{asset_name}))
          [asset_qname, (asset_content assets_repo_qname, asset_path)]
        else
          [asset_qname, nil]
        end
      }.to_h

      insert_assets = if asset? assets_repo_qname, 'inserts'
        (asset_content assets_repo_qname, 'inserts').map {|asset_path|
          [%(images/#{asset_qpath = ::File.join 'inserts', asset_path}), (asset_content assets_repo_qname, asset_qpath)]
        }.to_h
      else
        { 'images/inserts/.gitkeep' => '' }
      end

      seed_files = {
        spine_doc_filename        => spine_doc_content,
        spine_config_filename     => spine_config.to_yaml.sub(/\A---\n/, ''),
        # TODO is there an API for managing gitignore we can use?
        '.gitignore'              => %W(/build/ /#{repo_name}-*/ /images/avatars/ /images/headshots/ /*.html /*.pdf*).join("\n"),
        'publishers-letter.adoc'  => (template_content assets_repo_qname, 'seed-publishers-letter.adoc', template_vars),
        'images/jacket/.gitkeep'  => ''
      }.merge(publisher_profile_assets).merge insert_assets

      seed_files.each do |filename, contents|
        if contents
          # TODO make a helper for creating files & adding to git index
          ::FileUtils.mkdir_p (::File.join repo_clone.workdir, (::File.dirname filename)) if filename.include? '/'
          ::File.open((::File.join repo_clone.workdir, filename), 'wb') {|fd| fd.write contents }
          index.add path: filename, oid: (::Rugged::Blob.from_workdir repo_clone, filename), mode: 0100644
        end
      end

      if asset? assets_repo_qname, 'styles'
        ::Dir.mkdir (::File.join repo_clone.workdir, 'styles')

        ['epub3.css', 'epub3-css3-only.css', 'pdf.yml'].each do |style_asset_name|
          if asset? assets_repo_qname, (style_asset_path = ::File.join 'styles', style_asset_name)
            style_asset_content = asset_content assets_repo_qname, style_asset_path
            ::File.open((::File.join repo_clone.workdir, style_asset_path), 'wb') {|fd| fd.write style_asset_content }
            index.add path: style_asset_path, oid: (::Rugged::Blob.from_workdir repo_clone, style_asset_path), mode: 0100644
          end
        end
      end

      ::File.unlink (::File.join repo_clone.workdir, 'README.md')
      index.remove 'README.md'

      commit_tree = index.write_tree repo_clone
      index.write

      commit_author = { name: @git_name, email: @git_email, time: ::Time.now }
      ::Rugged::Commit.create repo_clone,
        author: commit_author,
        committer: commit_author,
        message: 'Seed spine document and create configuration file',
        parents: [repo_clone.head.target],
        tree: commit_tree,
        update_ref: 'HEAD'

      ::Refined::Repository.push repo_clone
    end
  end

  # QUESTION should we move template_content to an Editions::TemplateManager class?
  # TODO create a method for retrieving raw contents (w/o substitutions)
  def template_content repo, path, vars = nil
    template_path = ::File.join 'templates', path
    content = if asset? repo, template_path
      asset_content repo, template_path
    else
      ::File.read (::File.join DATADIR, template_path)
    end

    unless vars.nil_or_empty?
      # TODO move regexp to constant
      content = content.gsub(/\{template-(.*?)\}/) { vars[$1] }
    end

    content
  end

  def asset? repo_qname, path
    if (dir = assets_clone_dir repo_qname)
      ::File.exist? (::File.join dir, path)
    else
      false
    end
  end

  def asset_content repo_qname, path
    asset_path = ::File.join (assets_clone_dir repo_qname), path
    if ::File.directory? asset_path
      ::Dir.chdir asset_path do
        ::Dir.glob '*' 
      end
    else
      ::File.binread asset_path
    end
  end

  # Clones the specified assets repository if necessary and returns the working directory.
  def assets_clone_dir repo_qname
    @assets_repo ||= begin
      clone_dir = (::File.join ::Dir.tmpdir, (::File.basename repo_qname))
      # TODO should we try to reuse an existing clone??
      ::FileUtils.rm_r clone_dir if ::File.exist? clone_dir
      ::Refined::Repository.clone_at (build_clone_url repo_qname), clone_dir
    rescue
      # no assets repository
      false
    end

    @assets_repo ? @assets_repo.workdir : nil
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
