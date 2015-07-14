require 'resque/tasks'

if ENV['RACK_ENV'] == 'test'
	require 'ci/reporter/rake/rspec'
	require 'rspec/core/rake_task'
	RSpec::Core::RakeTask.new(:spec => ["ci:setup:rspec"])
	task :default => [:spec]
else
	task :default => ['resque:work']
end