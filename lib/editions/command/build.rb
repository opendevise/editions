require 'asciidoctor-epub3'
require 'asciidoctor/extensions'

desc 'Build the periodical into one or more supported formats (e.g., epub3, kf8, pdf)'
command :build do |cmd|; cmd.instance_eval do
  flag :e, :edition,
    arg_name: '<edition>',
    desc: 'The volume and issue number of this edition (e.g., 5.1)',
    # Editions::EditionNumber parses volume and issue number parts into an Array
    type: Editions::EditionNumber,
    must_match: Editions::EditionNumberRx

  switch :V, :validate,
    desc: 'Perform validation (currently only applies to epub3 format)',
    negatable: false,
    default_value: false

  switch :x, :extract,
    desc: 'Extract the e-book into a folder in the build directory after building (applies to e-book formats)',
    negatable: false,
    default_value: false

  config_required

  action do |global, opts, args, config = global.config|
    edition_config = if File.exist? 'config.yml'
      OpenStruct.new (YAML.load_file 'config.yml', safe: true)
    else
      OpenStruct.new 
    end

    unless (edition_number = edition_config.edition || opts.edition)
      help_now! 'Could not determine the edition number. Are you sure you\'re in a directory containing the edition to build?'
    end

    edition = Editions::Edition.new edition_number, nil, nil, (periodical = Editions::Periodical.from config)

    unless File.exist? (spine_doc = %(#{edition.handle}.adoc))
      help_now! %(Could not find spine document: #{spine_doc})
    end

    # move the profile images into common area
    # FIXME move this logic to a helper method
    ::FileUtils.mkdir_p %w(images/avatars images/headshots)
    if ::File.readable? 'publisher-avatar.jpg'
      ::FileUtils.cp 'publisher-avatar.jpg', %(images/avatars/publisher.jpg)
    end
    if ::File.readable? 'publisher-headshot.jpg'
      ::FileUtils.cp 'publisher-headshot.jpg', %(images/headshots/publisher.jpg)
    end
    edition_config.articles.each do |article|
      if ::File.readable? (avatar = %(#{article['localDir']}/avatar.jpg))
        ::FileUtils.cp avatar, %(images/avatars/#{article['username']}.jpg)
      else
        ::Dir[%(#{article['localDir']}/*-avatar.jpg)].each do |avatar|
          ::FileUtils.cp avatar, %(images/avatars/#{(::File.basename avatar).sub '-avatar', ''})
        end
      end
      if ::File.readable? (headshot = %(#{article['localDir']}/headshot.jpg))
        ::FileUtils.cp headshot, %(images/headshots/#{article['username']}.jpg)
      else
        ::Dir[%(#{article['localDir']}/*-headshot.jpg)].each do |headshot|
          ::FileUtils.cp headshot, %(images/headshots/#{(::File.basename headshot).sub '-headshot', ''})
        end
      end
    end

    # TODO validate at least one given
    formats = ((args[0] || 'epub3,kf8').split ',') & ['epub3', 'kf8', 'pdf']

    to_file = nil
    to_dir = edition_config.buildDir || 'build'
    validate = opts.validate
    extract = opts.extract
    # TODO auto-detect non-editor or add commandline flag
    build_for = 'editor'

    pygments_attributes = (Gem::try_activate 'pygments.rb') ? ' source-highlighter=pygments pygments-css=style pygments-style=bw' : nil
    styles_attribute = (::File.exist? 'styles/epub3.css') ? ' epub3-stylesdir=styles' : nil

    # FIXME gepub has conflict with gli's version method
    GLI::App.send :undef_method, :version

    # TODO move extension to separate file
    Asciidoctor::Extensions.register do
      next unless @document.backend.to_s == 'epub3'
      treeprocessor do
        process do |document|
          if document.blocks? && (last_section = document.sections[-1]) && (last_section.title == 'About the Author')
            if (bio_para_1 = last_section.blocks[0]) && bio_para_1.context == :paragraph
              bio_para_1.lines.unshift %(image:headshots/#{document.attr 'username'}.jpg[author headshot,role=headshot])
              Asciidoctor::Document::AttributeEntry.new('imagesdir', 'images').save_to bio_para_1.attributes
            end
          end
        end
      end
    end

    formats.each do |format|
      Asciidoctor::Epub3::Converter.convert_file spine_doc,
          ebook_format: format, safe: :safe, to_dir: to_dir, to_file: to_file, validate: validate, extract: extract,
          attributes: %(listing-caption=Listing buildfor-#{build_for} builder=editions builder-editions#{styles_attribute}#{pygments_attributes})
    end
  end
end; end
