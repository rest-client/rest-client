require 'rake'
require 'spec/rake/spectask'

desc "Run all specs"
Spec::Rake::SpecTask.new('spec') do |t|
	t.spec_files = FileList['spec/*_spec.rb']
end

desc "Print specdocs"
Spec::Rake::SpecTask.new(:doc) do |t|
	t.spec_opts = ["--format", "specdoc", "--dry-run"]
	t.spec_files = FileList['spec/*_spec.rb']
end

desc "Run all examples with RCov"
Spec::Rake::SpecTask.new('rcov') do |t|
	t.spec_files = FileList['spec/*_spec.rb']
	t.rcov = true
	t.rcov_opts = ['--exclude', 'examples']
end

task :default => :spec

######################################################

require 'rake'
require 'rake/testtask'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'fileutils'

version = "0.1"
name = "rest-client"

spec = Gem::Specification.new do |s|
	s.name = name
	s.version = version
	s.summary = "Simple REST client for Ruby, inspired by microframework syntax for specifying actions."
	s.description = "A simple REST client for Ruby, inspired by the microframework (Camping, Sinatra...) style of specifying actions: get, put, post, delete."
	s.author = "Adam Wiggins"
	s.email = "adam@heroku.com"

	s.platform = Gem::Platform::RUBY
	
	s.files = %w(Rakefile) + Dir.glob("{lib,spec}/**/*")
	
	s.require_path = "lib"
end

Rake::GemPackageTask.new(spec) do |p|
	p.need_tar = true if RUBY_PLATFORM !~ /mswin/
end

task :install => [ :package ] do
	sh %{sudo gem install pkg/#{name}-#{version}.gem}
end

task :uninstall => [ :clean ] do
	sh %{sudo gem uninstall #{name}}
end

Rake::TestTask.new do |t|
	t.libs << "spec"
	t.test_files = FileList['spec/*_spec.rb']
	t.verbose = true
end

CLEAN.include [ 'pkg', '*.gem', '.config' ]

