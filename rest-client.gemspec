file_directory = File.dirname(__FILE__).gsub("(eval at ", "")
$:.unshift(File.join(file_directory, "lib"))
require File.expand_path("lib/restclient/version.rb", file_directory)

spec = Gem::Specification.new do |s|
  s.name = "rest-client"
  s.version = RestClient::VERSION
  s.authors = ["REST Client Team"]
  s.description = "A simple HTTP and REST client for Ruby, inspired by the Sinatra microframework style of specifying actions: get, put, post, delete."
  s.license = "MIT"
  s.email = "humans@chef.io"
  s.executables = ["restclient"]
  s.extra_rdoc_files = ["README.md", "history.md"]

  # Use a more robust approach for determining files
  begin
    # Change to the gemspec directory to ensure git command works correctly
    Dir.chdir(File.dirname(__FILE__)) do
      s.files = `git ls-files -z`.split("\0")
    end
  rescue StandardError
    # Fallback to Dir.glob if git is not available or fails
    s.files = Dir.glob("**/*").select { |f| File.file?(f) }
  end

  s.homepage = "https://github.com/rest-client/rest-client"
  s.summary = "Simple HTTP and REST client for Ruby, inspired by microframework syntax for specifying actions."

  s.add_development_dependency("cookstyle", "~> 8.4")
  s.add_development_dependency("pry", "~> 0")
  s.add_development_dependency("pry-doc", "~> 0")
  s.add_development_dependency("rdoc", ">= 2.4.2", "< 6.0")
  s.add_development_dependency("rspec", "~> 3.0")
  s.add_development_dependency("webmock", "~> 2.0")

  s.add_dependency("base64")
  s.add_dependency("http-accept", "~> 2.1.0")
  s.add_dependency("http-cookie", ">= 1.0.2", "< 2.0")
  s.add_dependency("mime-types", ">= 1.16", "< 4.0")
  s.add_dependency("netrc", "~> 0.8")

  # Add FFI dependency for Windows platforms
  s.add_dependency("ffi", ">= 1.15.5", "< 1.18.0") if Gem.win_platform?

  s.required_ruby_version = ">= 3.1.0"
end

spec
