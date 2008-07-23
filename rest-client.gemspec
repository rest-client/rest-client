Gem::Specification.new do |s|
    s.name = "rest-client"
    s.version = "0.6.2"
    s.summary = "Simple REST client for Ruby, inspired by microframework syntax for specifying actions."
    s.description = "A simple REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete."
    s.author = "Adam Wiggins"
    s.email = "adam@heroku.com"
    s.rubyforge_project = "rest-client"
    s.homepage = "http://rest-client.heroku.com/"
    s.has_rdoc = true
    s.platform = Gem::Platform::RUBY
    s.files = %w(Rakefile README.rdoc rest-client.gemspec 
                 lib/request_errors.rb lib/resource.rb lib/rest_client.rb 
                 spec/base.rb spec/request_errors_spec.rb spec/resource_spec.rb spec/rest_client_spec.rb
                 bin/restclient)
    s.executables = ['restclient']
    s.require_path = "lib"
end
