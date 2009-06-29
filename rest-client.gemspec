# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{rest-client}
  s.version = "1.0.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Adam Wiggins"]
  s.date = %q{2009-06-29}
  s.default_executable = %q{restclient}
  s.description = %q{A simple REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete.}
  s.email = %q{adam@heroku.com}
  s.executables = ["restclient"]
  s.extra_rdoc_files = [
    "README.rdoc"
  ]
  s.files = [
    "README.rdoc",
     "Rakefile",
     "VERSION",
     "bin/restclient",
     "lib/rest_client.rb",
     "lib/restclient.rb",
     "lib/restclient/exceptions.rb",
     "lib/restclient/mixin/response.rb",
     "lib/restclient/raw_response.rb",
     "lib/restclient/request.rb",
     "lib/restclient/resource.rb",
     "lib/restclient/response.rb",
     "spec/base.rb",
     "spec/exceptions_spec.rb",
     "spec/mixin/response_spec.rb",
     "spec/raw_response_spec.rb",
     "spec/request_spec.rb",
     "spec/resource_spec.rb",
     "spec/response_spec.rb",
     "spec/restclient_spec.rb"
  ]
  s.has_rdoc = true
  s.homepage = %q{http://rest-client.heroku.com/}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{rest-client}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Simple REST client for Ruby, inspired by microframework syntax for specifying actions.}
  s.test_files = [
    "spec/base.rb",
     "spec/exceptions_spec.rb",
     "spec/mixin/response_spec.rb",
     "spec/raw_response_spec.rb",
     "spec/request_spec.rb",
     "spec/resource_spec.rb",
     "spec/response_spec.rb",
     "spec/restclient_spec.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
