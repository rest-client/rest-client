require 'rake'

require 'jeweler'

Jeweler::Tasks.new do |s|
  s.name = "rest-client"
  s.description = "A simple HTTP and REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete."
  s.summary = "Simple HTTP and REST client for Ruby, inspired by microframework syntax for specifying actions."
  s.authors = ["Adam Wiggins", "Julien Kirch"]
  s.email = "rest.client@librelist.com"
  s.homepage = "http://github.com/archiloque/rest-client"
  s.files = FileList["[A-Z]*", "{bin,lib,spec}/**/*"]
  s.test_files = FileList["{spec}/**/*"]
  s.add_runtime_dependency("mime-types", ">= 1.16")
  s.add_development_dependency("webmock", ">= 0.9.1")
  s.add_development_dependency("rspec")
  s.extra_rdoc_files = [ 'README.rdoc', 'history.md']
end

############################

require "rspec/core/rake_task"

desc "Run all specs"
task :spec => ["spec:unit", "spec:integration"]

desc "Run unit specs"
RSpec::Core::RakeTask.new('spec:unit') do |t|
  t.rspec_opts = ['--colour --format progress']
  t.pattern = 'spec/*_spec.rb'
end

desc "Run integration specs"
RSpec::Core::RakeTask.new('spec:integration') do |t|
  t.rspec_opts = ['--colour --format progress']
  t.pattern = 'spec/integration/*_spec.rb'
end

desc "Print specdocs"
RSpec::Core::RakeTask.new(:doc) do |t|
  t.rspec_opts = ["--format", "specdoc", "--dry-run"]
  t.pattern = 'spec/*_spec.rb'
end

desc "Run all examples with RCov"
RSpec::Core::RakeTask.new('rcov') do |t|
  t.pattern = 'spec/*_spec.rb'
  t.rcov = true
  t.rcov_opts = ['--exclude', 'examples']
end

task :default => :spec

############################

require 'rdoc/task'

Rake::RDocTask.new do |t|
  t.rdoc_dir = 'rdoc'
  t.title    = "rest-client, fetch RESTful resources effortlessly"
  t.options << '--line-numbers' << '--inline-source' << '-A cattr_accessor=object'
  t.options << '--charset' << 'utf-8'
  t.rdoc_files.include('README.rdoc')
  t.rdoc_files.include('lib/*.rb')
end

