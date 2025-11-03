source "https://rubygems.org"

gemspec name: "rest-client"

if RUBY_PLATFORM =~ /mingw|mswin/
  gem "fiddle", "= 1.1.0"
else
  gem "fiddle", "~> 1.1.8"
end

group :test do
  gem "rake"
end
