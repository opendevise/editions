# -*- encoding: utf-8 -*-
require File.expand_path('lib/editions/version', File.dirname(__FILE__))

Gem::Specification.new do |s| 
  s.name = 'editions'
  s.version = Editions::VERSION

  s.summary = 'Publish periodicals generated from articles composed in AsciiDoc'
  s.description = <<-EOS
A toolchain for publishing periodicals that are aggregated from articles stored in GitHub repositories and composed in AsciiDoc.
  EOS

  s.author = 'OpenDevise Inc.'
  s.email = 'editions@opendevise.io'
  s.homepage = 'http://opendevise.io/projects/editions'
  s.license = 'MIT'

  s.required_ruby_version = '>= 1.9'

  begin
    s.files = `git ls-files -z -- */* {README.adoc,LICENSE.adoc,Rakefile}`.split "\0"
  rescue
    s.files = Dir['**/*']
  end

  s.executables = %w(editions)
  s.test_files = s.files.grep(/^(?:test|spec|feature)\/.*$/)
  s.require_paths = %w(lib)

  s.has_rdoc = true
  s.rdoc_options = %(--charset=UTF-8 --title=Editions --main=README.adoc -ri)
  s.extra_rdoc_files = %w(README.adoc LICENSE.adoc)

  s.add_development_dependency 'rake', '~> 10.0'
  s.add_development_dependency 'rdoc', '~> 4.1.0'
  s.add_development_dependency 'aruba', '~> 0.5.4'

  s.add_runtime_dependency 'gli', '~> 2.10.0'
  s.add_runtime_dependency 'octokit', '~> 3.1.0'
  s.add_runtime_dependency 'commander', '~> 4.2.0'
  s.add_runtime_dependency 'rugged', '~> 0.19.0'
  s.add_runtime_dependency 'asciidoctor', ['>= 1.5.0.rc.2', '< 1.6.0']
  s.add_runtime_dependency 'asciidoctor-epub3', '1.0.0.alpha.1'
  s.add_runtime_dependency 'asciidoctor-pdf', '1.0.0.dev'
  s.add_runtime_dependency 'rmagick', '~> 2.13.2'
  s.add_runtime_dependency 'safe_yaml', '~> 1.0.3'

  # optional
  #s.add_runtime_dependency 'netrc', '0.7.7'
end
