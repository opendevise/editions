module Refined
class Submodule
  class << self
    def add repository, path, url, oid, options = {}
      ::File.open ::File.join(repository.workdir, '.gitmodules'), 'a+' do |fd|
        fd.read # make sure we're at the end of the file
        fd.write "\n\n" unless fd.pos == 0 
        fd.write %([submodule "#{path}"]
\tpath = #{path}
\turl = #{url})
      end

      index = options[:index] || repository.index
      index.add path: '.gitmodules',
        oid: (::Rugged::Blob.from_workdir repository, '.gitmodules'),
        mode: 0100644

      index.add path: path, oid: oid, mode: 0160000
      nil
    end
  end
end
end
