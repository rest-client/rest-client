require_relative '_lib'
require 'json'

describe RestClient::Request do
  before(:all) do
    WebMock.disable!
  end

  after(:all) do
    WebMock.enable!
  end

  def default_httpbin_url
    # add a hack to work around java/jruby bug
    # java.lang.RuntimeException: Could not generate DH keypair with backtrace
    if ENV['TRAVIS_RUBY_VERSION'] == 'jruby-19mode'
      'http://httpbin.org/'
    else
      'https://httpbin.org/'
    end
  end

  def httpbin(suffix='')
    url = ENV.fetch('HTTPBIN_URL', default_httpbin_url)
    unless url.end_with?('/')
      url += '/'
    end

    url + suffix
  end

  def execute_httpbin(suffix, opts={})
    opts = {url: httpbin(suffix)}.merge(opts)
    RestClient::Request.execute(opts)
  end

  def execute_httpbin_json(suffix, opts={})
    JSON.parse(execute_httpbin(suffix, opts))
  end

  describe '.execute' do
    it 'sends a user agent' do
      data = execute_httpbin_json('user-agent', method: :get)
      data['user-agent'].should match(/rest-client/)
    end

    it 'receives cookies on 302' do
      expect {
        execute_httpbin('cookies/set?foo=bar', method: :get, max_redirects: 0)
      }.to raise_error(RestClient::Found) { |ex|
        ex.http_code.should eq 302
        ex.response.cookies['foo'].should eq 'bar'
      }
    end

    it 'passes along cookies through 302' do
      data = execute_httpbin_json('cookies/set?foo=bar', method: :get)
      data.should have_key('cookies')
      data['cookies']['foo'].should eq 'bar'
    end

    it 'handles quote wrapped cookies' do
      expect {
        execute_httpbin('cookies/set?foo=' + CGI.escape('"bar:baz"'),
                        method: :get, max_redirects: 0)
      }.to raise_error(RestClient::Found) { |ex|
        ex.http_code.should eq 302
        ex.response.cookies['foo'].should eq '"bar:baz"'
      }
    end

    it 'keeps original cookies for the domain' do
      response = execute_httpbin('cookies/set?foo=bar', method: :get, cookies: { baz: 'quux; Path=/' })
      response.cookies['foo'].should eq 'bar'
      response.cookies['baz'].should eq 'quux'
    end

    it 'overwrites original cookies with new cookies if present' do
      response = execute_httpbin('cookies/set?foo=bar', method: :get, cookies: { foo: 'quux; Path=/' })
      response.cookies['foo'].should eq 'bar'
    end
  end
end
