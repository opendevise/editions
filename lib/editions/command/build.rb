require 'asciidoctor/extensions'
require 'asciidoctor-epub3'
require_relative '../cover_annotator'
#require 'asciidoctor/pdf_renderer'
#require 'editions/pdf_extensions'

desc 'Build the publication into one or more of the supported formats (e.g., epub3, kf8, pdf)'
command :build do |cmd|; cmd.instance_eval do
  SUPPORTED_FORMATS = %w(epub3 kf8 pdf)

  flag :f, :for,
    arg_name: '<login>',
    desc: 'Selectively build for the specified author (identified by login) (e.g., octocat)'

  switch :V, :validate,
    desc: 'Perform validation (currently only applies to epub3 format)',
    negatable: false,
    default_value: false

  switch :z, :optimize,
    desc: 'Optimized the generated file (applies to pdf format)',
    negatable: false,
    default_value: false

  switch :x, :extract,
    desc: 'Extract the e-book into a folder in the build directory after building (applies to e-book formats)',
    negatable: false,
    default_value: false

  action do |global, opts, args, config = global.config|
    edition_config = if File.exist? 'config.yml'
      OpenStruct.new (YAML.load_file 'config.yml', safe: true)
    else
      help_now! 'Could not locate edition to build. Are you in the directory of the edition you want to build?'
    end

    #edition = Editions::Edition.new edition_number, nil, nil, (Editions::Publication.from config)
    #edition_handle = edition.handle
    edition_handle = edition_config.edition_handle

    unless File.exist? (spine_doc = %(#{edition_handle}.adoc))
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
      if ::File.readable? (avatar = %(#{article['local_dir']}/avatar.jpg))
        ::FileUtils.cp avatar, %(images/avatars/#{article['username']}.jpg)
      else
        ::Dir[%(#{article['local_dir']}/*-avatar.jpg)].each do |avatar|
          ::FileUtils.cp avatar, %(images/avatars/#{(::File.basename avatar).sub '-avatar', ''})
        end
      end
      if ::File.readable? (headshot = %(#{article['local_dir']}/headshot.jpg))
        ::FileUtils.cp headshot, %(images/headshots/#{article['username']}.jpg)
      else
        ::Dir[%(#{article['local_dir']}/*-headshot.jpg)].each do |headshot|
          ::FileUtils.cp headshot, %(images/headshots/#{(::File.basename headshot).sub '-headshot', ''})
        end
      end
    end

    # TODO validate at least one given
    formats = if (formats_arg = args[0])
      (formats_arg.split ',') & SUPPORTED_FORMATS
    else
      SUPPORTED_FORMATS.dup
    end

    to_dir = edition_config.build_dir || 'build'
    ::FileUtils.mkdir_p to_dir unless ::File.directory? to_dir
    validate = opts.validate
    extract = opts.extract
    # TODO auto-detect non-editor (how?)
    build_for = opts.for || 'editor'

    #pygments_attributes = (Gem::try_activate 'pygments.rb') ? ' source-highlighter=pygments pygments-css=style pygments-style=bw' : nil
    styles_attribute = (::File.exist? 'styles/epub3.css') ? ' epub3-stylesdir=styles' : nil

    # FIXME gepub has conflict with gli's version method
    GLI::App.send :undef_method, :version

    begin
      Editions::CoverAnnotator.new.annotate if Editions::CoverAnnotator.needs_annotating?
    rescue StandardError => e
      warn %(editions: Could not annotate cover: #{e.message})
    end

    # TODO move extension to separate file
    Asciidoctor::Extensions.register do
      next unless @document.backend.to_s == 'epub3-xhtml5'
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
      case format
      #when 'html'
      # not yet implemented
      when 'epub3', 'kf8'
        # QUESTION should we rely on listing-caption=Listing being defined in Asciidoctor EPUB?
        Asciidoctor.convert_file spine_doc, safe: :safe, to_dir: to_dir, backend: :epub3,
            attributes: %(compat-mode=@ buildfor=#{build_for} buildfor-#{build_for} builder=editions builder-editions#{styles_attribute} ebook-format=#{format}#{validate ? ' ebook-validate' : nil}#{extract ? ' ebook-extract' : nil})
      when 'pdf'
        out, err, code = Open3.capture3 %(asciidoctor-pdf --trace -a compat-mode=@ -a pagenums -a buildfor=editor -a buildfor-editor -a env=editions -a env-editions -a builder=editions -a builder-editions -a notitle -a pdf-stylesdir=styles -a pdf-style=pdf.yml -r #{File.dirname __FILE__}/../pdf_extensions -D #{to_dir} #{spine_doc})
        puts out unless out.empty?
        warn err unless err.empty?
        if opts.optimize
          # TODO set IMAGE_DPI=300 env var
          _, _, _ = Open3.capture3 %(optimize-pdf #{File.join to_dir, edition_handle}.pdf)
        end
      end
    end
  end
end; end
