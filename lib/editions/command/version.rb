desc 'Outputs the version of this program and exits'
command :version do |cmd|
  cmd.action do
    say %(editions version #{Editions::VERSION})
  end
end
