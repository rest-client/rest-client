# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = 'rest-client'
  s.version = '1.7.0.alpha'
  s.authors = ['REST Client Team']
  s.description = 'A simple HTTP and REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete.'
  s.license = 'MIT'
  s.email = 'rest.client@librelist.com'
  s.executables = ['restclient']
  s.extra_rdoc_files = ["README.rdoc", "history.md"]
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- spec/*`.split("\n")
  s.homepage = 'http://github.com/rest-client/rest-client'
  s.summary = 'Simple HTTP and REST client for Ruby, inspired by microframework syntax for specifying actions.'

  s.add_runtime_dependency(%q<mime-types>, [">= 1.16"])
  s.add_runtime_dependency(%q<net-http-persistent>)
  s.add_development_dependency(%q<webmock>, [">= 0.9.1"])
  s.add_development_dependency(%q<rspec>, [">= 2.0"])
  s.add_dependency(%q<netrc>, ["~> 0.7.7"])
end

