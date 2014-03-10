desc 'Clone the article repositories'
command :clone do |cmd|; cmd.instance_eval do
  flag :C, :directory,
    arg_name: '<directory>',
    desc: 'Create and change to directory <directory>'

  flag :p, :period,
    arg_name: '<date>',
    desc: %(The period of the issue (e.g., #{Time.now.strftime '%Y-%m'})),
    default_value: (Time.now.strftime '%Y-%m')

  action do |global, opts, args|
    say 'clone'
  end
end; end
