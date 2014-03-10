When /^I invoke the "(.*?)(?: (.*?))?" command(?: without specifying a profile)?$/ do |app_name, args|
  @app_name = app_name
  step %(I run `#{app_name} #{args}`)
end

When /^I invoke the "(.*?) (.*?)" command with the profile "(\w+)"$/ do |app_name, args, profile|
  @app_name = app_name
  step %(I run `#{app_name} -P#{profile} #{args}`)
end

When /^I invoke the command "(.*?) (.*?)" interactively$/ do |app_name, args|
  @app_name = app_name
  args = args.gsub(/(EDITIONS_[A-Z_]+)/) { ENV[$1] } if args.include? 'EDITIONS_'
  step %(I run `#{app_name} #{args}` interactively)
end

When /^I type the text from the environment variable "(.*?)"$/ do |name|
  type ENV[name]
end

# Add more step definitions here
