# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = 'rest_client'
  s.version = '1.7.3'
  s.authors = ['REST Client Team']
  s.description = 'Same as rest-client, but removes mime-types dependency. -- A simple HTTP and REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete.'
  s.license = 'MIT'
  s.email = 'rest.client@librelist.com'
  s.executables = ['restclient']
  s.extra_rdoc_files = ["README.rdoc", "history.md"]
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- spec/*`.split("\n")
  s.homepage = 'http://github.com/rest-client/rest-client'
  s.summary = 'Simple HTTP and REST client for Ruby, inspired by microframework syntax for specifying actions.'

  s.add_dependency(%q<netrc>, ["~> 0.7.7"])
  s.add_development_dependency(%q<webmock>, ["~> 1.4"])
  s.add_development_dependency(%q<rspec>, ["~> 2.4"])
  s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
end

