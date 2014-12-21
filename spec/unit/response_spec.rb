require 'spec_helper'

describe RestClient::Response do
  before do
    @net_http_res = double('net http response', :to_hash => {"Status" => ["200 OK"]}, :code => 200)
    @request = double('http request', :user => nil, :password => nil)
    @response = RestClient::Response.create('abc', @net_http_res, {})
  end

  it "behaves like string" do
    expect(@response.to_s).to eq 'abc'
    expect(@response.to_str).to eq 'abc'
    expect(@response.to_i).to eq 200
  end

  it "accepts nil strings and sets it to empty for the case of HEAD" do
    expect(RestClient::Response.create(nil, @net_http_res, {}).to_s).to eq ""
  end

  it "test headers and raw headers" do
    expect(@response.raw_headers["Status"][0]).to eq "200 OK"
    expect(@response.headers[:status]).to eq "200 OK"
  end

  describe "cookie processing" do
    it "should correctly deal with one Set-Cookie header with one cookie inside" do
      net_http_res = double('net http response', :to_hash => {"etag" => ["\"e1ac1a2df945942ef4cac8116366baad\""], "set-cookie" => ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT"]})
      response = RestClient::Response.create('abc', net_http_res, {})
      expect(response.headers[:set_cookie]).to eq ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT"]
      expect(response.cookies).to eq({ "main_page" => "main_page_no_rewrite" })
    end

    it "should correctly deal with multiple cookies [multiple Set-Cookie headers]" do
      net_http_res = double('net http response', :to_hash => {"etag" => ["\"e1ac1a2df945942ef4cac8116366baad\""], "set-cookie" => ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT", "remember_me=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT", "user=somebody; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT"]})
      response = RestClient::Response.create('abc', net_http_res, {})
      expect(response.headers[:set_cookie]).to eq ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT", "remember_me=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT", "user=somebody; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT"]
      expect(response.cookies).to eq({
        "main_page" => "main_page_no_rewrite",
        "remember_me" => "",
        "user" => "somebody"
      })
    end

    it "should correctly deal with multiple cookies [one Set-Cookie header with multiple cookies]" do
      net_http_res = double('net http response', :to_hash => {"etag" => ["\"e1ac1a2df945942ef4cac8116366baad\""], "set-cookie" => ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT, remember_me=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT, user=somebody; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT"]})
      response = RestClient::Response.create('abc', net_http_res, {})
      expect(response.cookies).to eq({
        "main_page" => "main_page_no_rewrite",
        "remember_me" => "",
        "user" => "somebody"
      })
    end
  end

  describe "exceptions processing" do
    it "should return itself for normal codes" do
      (200..206).each do |code|
        net_http_res = double('net http response', :code => '200')
        response = RestClient::Response.create('abc', net_http_res, {})
        response.return! @request
      end
    end

    it "should throw an exception for other codes" do
      RestClient::Exceptions::EXCEPTIONS_MAP.each_key do |code|
        unless (200..207).include? code
          net_http_res = double('net http response', :code => code.to_i)
          response = RestClient::Response.create('abc', net_http_res, {})
          expect { response.return!}.to raise_error
        end
      end
    end

  end

  describe "redirection" do

    it "follows a redirection when the request is a get" do
      stub_request(:get, 'http://some/resource').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://new/resource'})
      stub_request(:get, 'http://new/resource').to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get).body).to eq 'Foo'
    end

    it "follows a redirection and keep the parameters" do
      stub_request(:get, 'http://foo:bar@some/resource').with(:headers => {'Accept' => 'application/json'}).to_return(:body => '', :status => 301, :headers => {'Location' => 'http://new/resource'})
      stub_request(:get, 'http://foo:bar@new/resource').with(:headers => {'Accept' => 'application/json'}).to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :user => 'foo', :password => 'bar', :headers => {:accept => :json}).body).to eq 'Foo'
    end

    it "follows a redirection and keep the cookies" do
      stub_request(:get, 'http://some/resource').to_return(:body => '', :status => 301, :headers => {'Set-Cookie' => 'Foo=Bar', 'Location' => 'http://new/resource', })
      stub_request(:get, 'http://new/resource').with(:headers => {'Cookie' => 'Foo=Bar'}).to_return(:body => 'Qux')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get).body).to eq 'Qux'
    end

    it "doesn't follow a 301 when the request is a post" do
      net_http_res = double('net http response', :code => 301)
      response = RestClient::Response.create('abc', net_http_res, {:method => :post})
      expect { response.return!(@request)}.to raise_error(RestClient::MovedPermanently)
    end

    it "doesn't follow a 302 when the request is a post" do
      net_http_res = double('net http response', :code => 302)
      response = RestClient::Response.create('abc', net_http_res, {:method => :post})
      expect { response.return!(@request)}.to raise_error(RestClient::Found)
    end

    it "doesn't follow a 307 when the request is a post" do
      net_http_res = double('net http response', :code => 307)
      response = RestClient::Response.create('abc', net_http_res, {:method => :post})
      expect { response.return!(@request)}.to raise_error(RestClient::TemporaryRedirect)
    end

    it "doesn't follow a redirection when the request is a put" do
      net_http_res = double('net http response', :code => 301)
      response = RestClient::Response.create('abc', net_http_res, {:method => :put})
      expect { response.return!(@request)}.to raise_error(RestClient::MovedPermanently)
    end

    it "follows a redirection when the request is a post and result is a 303" do
      stub_request(:put, 'http://some/resource').to_return(:body => '', :status => 303, :headers => {'Location' => 'http://new/resource'})
      stub_request(:get, 'http://new/resource').to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :put).body).to eq 'Foo'
    end

    it "follows a redirection when the request is a head" do
      stub_request(:head, 'http://some/resource').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://new/resource'})
      stub_request(:head, 'http://new/resource').to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :head).body).to eq 'Foo'
    end

    it "handles redirects with relative paths" do
      stub_request(:get, 'http://some/resource').to_return(:body => '', :status => 301, :headers => {'Location' => 'index'})
      stub_request(:get, 'http://some/index').to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get).body).to eq 'Foo'
    end

    it "handles redirects with relative path and query string" do
      stub_request(:get, 'http://some/resource').to_return(:body => '', :status => 301, :headers => {'Location' => 'index?q=1'})
      stub_request(:get, 'http://some/index?q=1').to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get).body).to eq 'Foo'
    end

    it "follow a redirection when the request is a get and the response is in the 30x range" do
      stub_request(:get, 'http://some/resource').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://new/resource'})
      stub_request(:get, 'http://new/resource').to_return(:body => 'Foo')
      expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get).body).to eq 'Foo'
    end

    it "follows no more than 10 redirections before raising error" do
      stub_request(:get, 'http://some/redirect-1').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://some/redirect-2'})
      stub_request(:get, 'http://some/redirect-2').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://some/redirect-2'})
      expect { RestClient::Request.execute(:url => 'http://some/redirect-1', :method => :get) }.to raise_error(RestClient::MaxRedirectsReached)
      expect(WebMock).to have_requested(:get, 'http://some/redirect-2').times(10)
    end

    it "follows no more than max_redirects redirections, if specified" do
      stub_request(:get, 'http://some/redirect-1').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://some/redirect-2'})
      stub_request(:get, 'http://some/redirect-2').to_return(:body => '', :status => 301, :headers => {'Location' => 'http://some/redirect-2'})
      expect { RestClient::Request.execute(:url => 'http://some/redirect-1', :method => :get, :max_redirects => 5) }.to raise_error(RestClient::MaxRedirectsReached)
      expect(WebMock).to have_requested(:get, 'http://some/redirect-2').times(5)
    end
  end


end
