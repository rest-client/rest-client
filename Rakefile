require 'rake'
require 'spec/rake/spectask'

desc "Run all specs"
Spec::Rake::SpecTask.new('spec') do |t|
	t.spec_opts = ['--colour --format progress --loadby mtime --reverse']
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

version = "0.9.2"
name = "rest-client"

spec = Gem::Specification.new do |s|
	s.name = name
	s.version = version
	s.summary = "Simple REST client for Ruby, inspired by microframework syntax for specifying actions."
	s.description = "A simple REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete."
	s.author = "Adam Wiggins"
	s.email = "adam@heroku.com"
	s.homepage = "http://rest-client.heroku.com/"
	s.rubyforge_project = "rest-client"

	s.platform = Gem::Platform::RUBY
	s.has_rdoc = true
	
	s.files = %w(Rakefile README.rdoc) + Dir.glob("{lib,spec}/**/*")
	s.executables = ['restclient']
	
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

Rake::RDocTask.new do |t|
	t.rdoc_dir = 'rdoc'
	t.title    = "rest-client, fetch RESTful resources effortlessly"
	t.options << '--line-numbers' << '--inline-source' << '-A cattr_accessor=object'
	t.options << '--charset' << 'utf-8'
	t.rdoc_files.include('README.rdoc')
	t.rdoc_files.include('lib/restclient.rb')
	t.rdoc_files.include('lib/restclient/*.rb')
end

CLEAN.include [ 'pkg', '*.gem', '.config' ]

