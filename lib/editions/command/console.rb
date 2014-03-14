
desc 'Starts a console in the context of the configured environment'
command :console do |cmd|; cmd.instance_eval do
  action do |global, opts, args|
    unless (config = global.config)
      exit_now! color(%(error: #{global.profile || 'default'} profile does not exist. Please run `config' to configure your environment.), :red)
    end

    @hub = Editions::Hub.connect config
    @manager = Editions::RepositoryManager.new @hub, config.git_name, config.git_email, config.repository_access
    require 'irb'
    IRB.setup nil
    IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
    require 'irb/ext/multi-irb'
    IRB.irb nil, self
  end
end; end
