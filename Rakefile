# load `rake build/install/release tasks'
require 'bundler/setup'
require_relative 'lib/contractful/version'

namespace :ruby do
  Bundler::GemHelper.install_tasks(name: 'contractful')
end

require 'rspec/core/rake_task'

desc 'Run all specs'
RSpec::Core::RakeTask.new('spec')

# COVERAGE_GATE makes spec_helper enforce the 95% line-coverage minimum
# (G13); the integration suite exercises a smaller slice of lib/ by design
# and must not be held to the unit suite's bar. COVERAGE_SUITE keeps the
# two resultsets from merging. The env vars are set in wrapper tasks because
# RSpec::Core::RakeTask has no env attribute; the RSpec tasks carry a :run
# suffix and stay private to this file.
desc 'Run unit specs (enforces the coverage gate)'
task 'spec:unit' do
  ENV['COVERAGE_GATE'] = '1'
  ENV['COVERAGE_SUITE'] = 'unit'
  Rake::Task['spec:unit:run'].invoke
end

RSpec::Core::RakeTask.new('spec:unit:run') do |t|
  # ** so the nested spec/unit/contract/ suite runs too
  t.pattern = 'spec/unit/**/*_spec.rb'
end

desc 'Run integration specs'
task 'spec:integration' do
  ENV['COVERAGE_SUITE'] = 'integration'
  Rake::Task['spec:integration:run'].invoke
end

RSpec::Core::RakeTask.new('spec:integration:run') do |t|
  t.pattern = 'spec/integration/*_spec.rb'
end

desc 'Run live-network integration specs (requires internet access)'
task 'spec:live' do
  ENV['COVERAGE_SUITE'] = 'live'
  ENV['LIVE_HTTP_TESTS'] = '1'
  Rake::Task['spec:live:run'].invoke
end

RSpec::Core::RakeTask.new('spec:live:run') do |t|
  t.pattern = 'spec/integration/*_spec.rb'
  t.rspec_opts = ['--tag', 'live']
end

desc 'Run RuboCop static analysis (see .rubocop.yml for the baseline strategy)'
require 'rubocop/rake_task'
RuboCop::RakeTask.new('rubocop')

desc 'Print specdocs'
RSpec::Core::RakeTask.new(:doc) do |t|
  t.rspec_opts = ['--format', 'specdoc', '--dry-run']
  t.pattern = 'spec/**/*_spec.rb'
end

task default: :spec

desc 'Regenerate authors file'
task :authors do
  Dir.chdir(File.dirname(__FILE__)) do
    File.write('AUTHORS', <<~EOM)
      The Ruby REST Client would not be what it is today without the help of
      the following kind souls:
      
    EOM

    sh 'git shortlog -s | cut -f 2 >> AUTHORS'
  end
end

############################

WINDOWS_PLATFORMS = %w[x86-mingw32 x64-mingw32 x64-mingw-ucrt]

namespace :all do
  desc "Build contractful #{Contractful::VERSION} for all platforms"
  task build: ['ruby:build'] + 
              WINDOWS_PLATFORMS.map { |p| "windows:#{p}:build" }

  desc "Create tag v#{Contractful::VERSION} and for all platforms build and " \
       "push contractful #{Contractful::VERSION} to Rubygems"
  task release: ['build', 'ruby:release'] + 
                WINDOWS_PLATFORMS.map { |p| "windows:#{p}:push" }
end

namespace :windows do
  spec_path = File.join(File.dirname(__FILE__), 'contractful.windows.gemspec')

  WINDOWS_PLATFORMS.each do |platform|
    namespace platform do
      gem_filename = "contractful-#{Contractful::VERSION}-#{platform}.gem"
      base = File.dirname(__FILE__)
      pkg_dir = File.join(base, 'pkg')
      gem_file_path = File.join(pkg_dir, gem_filename)

      desc "Build #{gem_filename} into the pkg directory"
      task 'build' do
        orig_platform = ENV.fetch('BUILD_PLATFORM', nil)
        begin
          ENV['BUILD_PLATFORM'] = platform

          sh("gem build -V #{spec_path}") do |ok, res|
            if ok
              FileUtils.mkdir_p(pkg_dir)
              FileUtils.mv(File.join(base, gem_filename), pkg_dir)
              Bundler.ui.confirm("contractful #{Contractful::VERSION} " \
                                 "built to pkg/#{gem_filename}")
            else
              abort "Command `gem build` failed: #{res}"
            end
          end
        ensure
          ENV['BUILD_PLATFORM'] = orig_platform
        end
      end

      desc "Push #{gem_filename} to Rubygems"
      task 'push' do
        sh("gem push #{gem_file_path}")
      end
    end
  end
end

############################

require 'rdoc/task'

Rake::RDocTask.new do |t|
  t.rdoc_dir = 'rdoc'
  t.title    = 'contractful, fetch RESTful resources effortlessly'
  t.options << '--line-numbers' << '--inline-source' << '-A cattr_accessor=object'
  t.options << '--charset' << 'utf-8'
  t.rdoc_files.include('README.md')
  t.rdoc_files.include('lib/*.rb')
end
