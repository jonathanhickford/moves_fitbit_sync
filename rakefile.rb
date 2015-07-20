if ENV['RACK_ENV'] == 'test'
	require 'ci/reporter/rake/rspec'
	require 'rspec/core/rake_task'
	RSpec::Core::RakeTask.new(:spec => ["ci:setup:rspec"])
	task :default => [:spec]
else
	require 'resque/tasks'
	require File.expand_path('../moves_notifications/moves_notifications', __FILE__)
	task :default => ['resque:work']
end
