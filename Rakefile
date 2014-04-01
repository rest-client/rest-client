begin
  # optionally load `rake build/install/release tasks'
  require 'bundler/gem_tasks'
rescue LoadError
end

require "rspec/core/rake_task"

desc "Run all specs"
RSpec::Core::RakeTask.new('spec')

desc "Run unit specs"
RSpec::Core::RakeTask.new('spec:unit') do |t|
  t.pattern = 'spec/unit/*_spec.rb'
end

desc "Run integration specs"
RSpec::Core::RakeTask.new('spec:integration') do |t|
  t.pattern = 'spec/integration/*_spec.rb'
end

desc "Print specdocs"
RSpec::Core::RakeTask.new(:doc) do |t|
  t.rspec_opts = ["--format", "specdoc", "--dry-run"]
  t.pattern = 'spec/**/*_spec.rb'
end

desc "Run all examples with RCov"
RSpec::Core::RakeTask.new('rcov') do |t|
  t.pattern = 'spec/*_spec.rb'
  t.rcov = true
  t.rcov_opts = ['--exclude', 'examples']
end

task :default do
  sh 'rake -T'
end

def alias_task(alias_task, original)
  desc "Alias for rake #{original}"
  task alias_task, Rake.application[original].arg_names => original
end
alias_task(:test, :spec)

############################

WindowsPlatforms = %w{x86-mingw32 x64-mingw32 x86-mswin32}

desc "build all platform gems at once"
task :gems => [:rm_gems, 'ruby:gem'] + \
               WindowsPlatforms.map {|p| "windows:#{p}:gem"}

task :rm_gems => ['ruby:clobber_package']

def built_gem_path
  base = '.'
  Dir[File.join(base, "#{name}-*.gem")].sort_by{|f| File.mtime(f)}.last
end

namespace :windows do
  spec_path = File.join(File.dirname(__FILE__), 'rest-client.gemspec')

  WindowsPlatforms.each do |platform|
    namespace platform do
      desc "build gem for #{platform}"
      task 'build' do
        orig_platform = ENV['BUILD_PLATFORM']
        begin
          ENV['BUILD_PLATFORM'] = platform

          sh("gem build -V #{spec_path + '.windows'}") do |ok, res|
            if !ok
              puts "not OK: #{ok.inspect} #{res.inspect}"
            end
          end

        ensure
          ENV['BUILD_PLATFORM'] = orig_platform
        end
      end
    end
  end

end

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

