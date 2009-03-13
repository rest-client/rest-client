Gem::Specification.new do |s|
    s.name = "rest-client"
    s.version = "0.9.2"
    s.summary = "Simple REST client for Ruby, inspired by microframework syntax for specifying actions."
    s.description = "A simple REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete."
    s.author = "Adam Wiggins"
    s.email = "adam@heroku.com"
    s.rubyforge_project = "rest-client"
    s.homepage = "http://rest-client.heroku.com/"
    s.has_rdoc = true
    s.platform = Gem::Platform::RUBY
    s.files = %w(Rakefile README.rdoc rest-client.gemspec
                 lib/rest_client.rb lib/restclient.rb
                 lib/restclient/request.rb lib/restclient/response.rb
                 lib/restclient/exceptions.rb lib/restclient/resource.rb
                 spec/base.rb spec/request_spec.rb spec/response_spec.rb
                 spec/exceptions_spec.rb spec/resource_spec.rb spec/restclient_spec.rb
                 bin/restclient)
    s.executables = ['restclient']
    s.require_path = "lib"
end
