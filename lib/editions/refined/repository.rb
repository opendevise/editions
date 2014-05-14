module Refined
class Repository
  class << self
    def clone_at clone_url, clone_dir, options = {}
      if ((clone_url.start_with? 'https://') && (::Rugged.features.include? :https)) || (::Rugged.features.include? :ssh)
        # QUESTION how do we handle a recursive checkout?
        ::Rugged::Repository.clone_at clone_url, clone_dir
      else
        # TODO check status.exitvalue
        out, err, status = ::Open3.capture3 %(git clone #{options[:recursive] ? '--recursive' : nil} #{clone_url} #{clone_dir})
        ::Rugged::Repository.new clone_dir
      end
    end

    def push repo, remote = 'origin', branch = 'master'
      if ::Rugged.features.include? :https
        repo.push remote, [%(refs/heads/#{branch})]
      else
        out, err, status = ::Open3.capture3 %(git push #{remote} #{branch}), chdir: repo.workdir
      end
    end
  end
end
end
