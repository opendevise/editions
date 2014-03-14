desc 'Outputs the version of this program and exits'
command :version do |cmd|
  cmd.action do |global, opts, args|
    say %(Editions #{Editions::VERSION})
  end
end
