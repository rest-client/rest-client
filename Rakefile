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
