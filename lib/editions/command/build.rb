require 'asciidoctor-epub3'
desc 'Build the periodical into one or more formats'
command :build do |cmd|; cmd.instance_eval do
  flag :p, :period,
    arg_name: '<date>',
    desc: %(The period of the issue (e.g., #{Time.now.strftime '%Y-%m'})),
    default_value: (Time.now.strftime '%Y-%m')

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
    master_doc = %(#{config.profile}-#{opts.period}.adoc)
    
    unless File.exist? master_doc
      help_now! %(could not find master (i.e., spine) document: #{master_doc})
    end

    # TODO validate at least one given
    formats = ((args.first || 'epub3,kf8').split ',') & ['epub3', 'kf8', 'pdf']

    to_file = nil
    to_dir = 'build'
    validate = opts.validate
    extract = opts.extract

    pygments_attributes = (Gem::try_activate 'pygments.rb') ? ' source-highlighter=pygments pygments-css=style pygments-style=bw' : nil

    # FIXME gepub has conflict with gli's version method
    GLI::App.send(:undef_method, :version)

    formats.each do |format|
      Asciidoctor::Epub3::Converter.convert_file master_doc,
          ebook_format: format, safe: :safe, to_dir: to_dir, to_file: to_file, validate: validate, extract: extract,
          attributes: %(listing-caption=Listing#{pygments_attributes} env-editions)
    end
  end
end; end
