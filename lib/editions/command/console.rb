desc 'Starts a console in the context of the configured environment'
command :console do |cmd|; cmd.instance_eval do
  # TODO would be nice if nodoc was a DSL method
  def nodoc
    true
  end

  config_required

  action do |global, opts, args, config = global.config|
    @hub = Editions::Hub.connect config
    @manager = Editions::RepositoryManager.new @hub, config.git_name, config.git_email, config.repository_access
    require 'irb'
    IRB.setup nil
    IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
    require 'irb/ext/multi-irb'
    IRB.irb nil, self
  end
end; end
