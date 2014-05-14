desc 'Outputs the version of this program and exits'
command :version do |cmd|
  cmd.action do
    say %(#{exe_name} version #{version_string})
  end
end
