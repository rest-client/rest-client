# -*- encoding: utf-8 -*-

require File.expand_path("../lib/restclient/version", __FILE__)

Gem::Specification.new do |s|
  s.name = 'rest-client'
  s.version = RestClient::VERSION
  s.authors = ['REST Client Team']
  s.description = 'A simple HTTP and REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete.'
  s.license = 'MIT'
  s.email = 'rest.client@librelist.com'
  s.executables = ['restclient']
  s.extra_rdoc_files = ["README.rdoc", "history.md"]
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- spec/*`.split("\n")
  s.homepage = 'https://github.com/rest-client/rest-client'
  s.summary = 'Simple HTTP and REST client for Ruby, inspired by microframework syntax for specifying actions.'

  s.add_dependency(%q<mime-types>, ["~> 1.16"])
  s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
  s.add_development_dependency(%q<rake>, ["~> 10.0"])
  s.add_development_dependency(%q<webmock>, ["~> 1.4"])
  s.add_development_dependency(%q<rspec>, ["~> 2.4"])
  s.add_development_dependency(%q<pry>)
end

