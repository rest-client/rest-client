require 'spec_helper'

describe RestClient::Request do
  before do
    @request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload')

    @uri = double("uri")
    allow(@uri).to receive(:request_uri).and_return('/resource')
    allow(@uri).to receive(:hostname).and_return('some')
    allow(@uri).to receive(:port).and_return(80)

    @net = double("net::http base")
    @http = double("net::http connection")
    allow(Net::HTTP).to receive(:new).and_return(@net)
    allow(@net).to receive(:start).and_yield(@http)
    allow(@net).to receive(:use_ssl=)
    allow(@net).to receive(:verify_mode=)
    allow(@net).to receive(:verify_callback=)
    allow(@net).to receive(:ciphers=)
    allow(@net).to receive(:cert_store=)
    RestClient.log = nil
  end

  it "accept */* mimetype" do
    expect(@request.default_headers[:accept]).to eq '*/*'
  end

  describe "compression" do

    it "decodes an uncompressed result body by passing it straight through" do
      expect(RestClient::Request.decode(nil, 'xyz')).to eq 'xyz'
    end

    it "doesn't fail for nil bodies" do
      expect(RestClient::Request.decode('gzip', nil)).to be_nil
    end


    it "decodes a gzip body" do
      expect(RestClient::Request.decode('gzip', "\037\213\b\b\006'\252H\000\003t\000\313T\317UH\257\312,HM\341\002\000G\242(\r\v\000\000\000")).to eq "i'm gziped\n"
    end

    it "ingores gzip for empty bodies" do
      expect(RestClient::Request.decode('gzip', '')).to be_empty
    end

    it "decodes a deflated body" do
      expect(RestClient::Request.decode('deflate', "x\234+\316\317MUHIM\313I,IMQ(I\255(\001\000A\223\006\363")).to eq "some deflated text"
    end
  end

  it "processes a successful result" do
    res = double("result")
    allow(res).to receive(:code).and_return("200")
    allow(res).to receive(:body).and_return('body')
    allow(res).to receive(:[]).with('content-encoding').and_return(nil)
    expect(@request.process_result(res).body).to eq 'body'
    expect(@request.process_result(res).to_s).to eq 'body'
  end

  it "doesn't classify successful requests as failed" do
    203.upto(207) do |code|
      res = double("result")
      allow(res).to receive(:code).and_return(code.to_s)
      allow(res).to receive(:body).and_return("")
      allow(res).to receive(:[]).with('content-encoding').and_return(nil)
      expect(@request.process_result(res)).to be_empty
    end
  end

  describe '.parse_url' do
    it "parses a url into a URI object" do
      expect(URI).to receive(:parse).with('http://example.com/resource')
      @request.parse_url('http://example.com/resource')
    end

    it "adds http:// to the front of resources specified in the syntax example.com/resource" do
      expect(URI).to receive(:parse).with('http://example.com/resource')
      @request.parse_url('example.com/resource')
    end

    it 'adds http:// to resources containing a colon' do
      expect(URI).to receive(:parse).with('http://example.com:1234')
      @request.parse_url('example.com:1234')
    end

    it 'does not add http:// to the front of https resources' do
      expect(URI).to receive(:parse).with('https://example.com/resource')
      @request.parse_url('https://example.com/resource')
    end

    it 'does not add http:// to the front of capital HTTP resources' do
      expect(URI).to receive(:parse).with('HTTP://example.com/resource')
      @request.parse_url('HTTP://example.com/resource')
    end

    it 'does not add http:// to the front of capital HTTPS resources' do
      expect(URI).to receive(:parse).with('HTTPS://example.com/resource')
      @request.parse_url('HTTPS://example.com/resource')
    end
  end

  describe "user - password" do
    it "extracts the username and password when parsing http://user:password@example.com/" do
      allow(URI).to receive(:parse).and_return(double('uri', :user => 'joe', :password => 'pass1'))
      @request.parse_url_with_auth('http://joe:pass1@example.com/resource')
      expect(@request.user).to eq 'joe'
      expect(@request.password).to eq 'pass1'
    end

    it "extracts with escaping the username and password when parsing http://user:password@example.com/" do
      allow(URI).to receive(:parse).and_return(double('uri', :user => 'joe%20', :password => 'pass1'))
      @request.parse_url_with_auth('http://joe%20:pass1@example.com/resource')
      expect(@request.user).to eq 'joe '
      expect(@request.password).to eq 'pass1'
    end

    it "doesn't overwrite user and password (which may have already been set by the Resource constructor) if there is no user/password in the url" do
      allow(URI).to receive(:parse).and_return(double('uri', :user => nil, :password => nil))
      @request = RestClient::Request.new(:method => 'get', :url => 'example.com', :user => 'beth', :password => 'pass2')
      @request.parse_url_with_auth('http://example.com/resource')
      expect(@request.user).to eq 'beth'
      expect(@request.password).to eq 'pass2'
    end
  end

  it "correctly formats cookies provided to the constructor" do
    allow(URI).to receive(:parse).and_return(double('uri', :user => nil, :password => nil))
    @request = RestClient::Request.new(:method => 'get', :url => 'example.com', :cookies => {:session_id => '1', :user_id => "someone" })
    expect(@request).to receive(:default_headers).and_return({'Foo' => 'bar'})
    expect(@request.make_headers({})).to eq({ 'Foo' => 'bar', 'Cookie' => 'session_id=1; user_id=someone'})
  end

  it "does not escape or unescape cookies" do
    cookie = 'Foo%20:Bar%0A~'
    @request = RestClient::Request.new(:method => 'get', :url => 'example.com',
                                       :cookies => {:test => cookie})
    expect(@request).to receive(:default_headers).and_return({'Foo' => 'bar'})
    expect(@request.make_headers({})).to eq({
      'Foo' => 'bar',
      'Cookie' => "test=#{cookie}"
    })
  end

  it "rejects cookie names containing invalid characters" do
    # Cookie validity is something of a mess, but we should reject the worst of
    # the RFC 6265 (4.1.1) prohibited characters such as control characters.

    ['', 'foo=bar', 'foo;bar', "foo\nbar"].each do |cookie_name|
      expect {
        RestClient::Request.new(:method => 'get', :url => 'example.com',
                                :cookies => {cookie_name => 'value'})
      }.to raise_error(ArgumentError, /\AInvalid cookie name/)
    end
  end

  it "rejects cookie values containing invalid characters" do
    # Cookie validity is something of a mess, but we should reject the worst of
    # the RFC 6265 (4.1.1) prohibited characters such as control characters.

    ['foo,bar', 'foo;bar', "foo\nbar"].each do |cookie_value|
      expect {
        RestClient::Request.new(:method => 'get', :url => 'example.com',
                                :cookies => {'test' => cookie_value})
      }.to raise_error(ArgumentError, /\AInvalid cookie value/)
    end
  end

  it "uses netrc credentials" do
    allow(URI).to receive(:parse).and_return(double('uri', :user => nil, :password => nil, :hostname => 'example.com'))
    allow(Netrc).to receive(:read).and_return('example.com' => ['a', 'b'])
    @request.parse_url_with_auth('http://example.com/resource')
    expect(@request.user).to eq 'a'
    expect(@request.password).to eq 'b'
  end

  it "uses credentials in the url in preference to netrc" do
    allow(URI).to receive(:parse).and_return(double('uri', :user => 'joe%20', :password => 'pass1', :hostname => 'example.com'))
    allow(Netrc).to receive(:read).and_return('example.com' => ['a', 'b'])
    @request.parse_url_with_auth('http://joe%20:pass1@example.com/resource')
    expect(@request.user).to eq 'joe '
    expect(@request.password).to eq 'pass1'
  end

  it "determines the Net::HTTP class to instantiate by the method name" do
    expect(@request.net_http_request_class(:put)).to eq Net::HTTP::Put
  end

  describe "user headers" do
    it "merges user headers with the default headers" do
      expect(@request).to receive(:default_headers).and_return({ :accept => '*/*', :accept_encoding => 'gzip, deflate' })
      headers = @request.make_headers("Accept" => "application/json", :accept_encoding => 'gzip')
      expect(headers).to have_key "Accept-Encoding"
      expect(headers["Accept-Encoding"]).to eq "gzip"
      expect(headers).to have_key "Accept"
      expect(headers["Accept"]).to eq "application/json"
    end

    it "prefers the user header when the same header exists in the defaults" do
      expect(@request).to receive(:default_headers).and_return({ '1' => '2' })
      headers = @request.make_headers('1' => '3')
      expect(headers).to have_key('1')
      expect(headers['1']).to eq '3'
    end

    it "converts user headers to string before calling CGI::unescape which fails on non string values" do
      expect(@request).to receive(:default_headers).and_return({ '1' => '2' })
      headers = @request.make_headers('1' => 3)
      expect(headers).to have_key('1')
      expect(headers['1']).to eq '3'
    end
  end

  describe "header symbols" do

    it "converts header symbols from :content_type to 'Content-Type'" do
      expect(@request).to receive(:default_headers).and_return({})
      headers = @request.make_headers(:content_type => 'abc')
      expect(headers).to have_key('Content-Type')
      expect(headers['Content-Type']).to eq 'abc'
    end

    it "converts content-type from extension to real content-type" do
      expect(@request).to receive(:default_headers).and_return({})
      headers = @request.make_headers(:content_type => 'json')
      expect(headers).to have_key('Content-Type')
      expect(headers['Content-Type']).to eq 'application/json'
    end

    it "converts accept from extension(s) to real content-type(s)" do
      expect(@request).to receive(:default_headers).and_return({})
      headers = @request.make_headers(:accept => 'json, mp3')
      expect(headers).to have_key('Accept')
      expect(headers['Accept']).to eq 'application/json, audio/mpeg'

      expect(@request).to receive(:default_headers).and_return({})
      headers = @request.make_headers(:accept => :json)
      expect(headers).to have_key('Accept')
      expect(headers['Accept']).to eq 'application/json'
    end

    it "only convert symbols in header" do
      expect(@request).to receive(:default_headers).and_return({})
      headers = @request.make_headers({:foo_bar => 'value', "bar_bar" => 'value'})
      expect(headers['Foo-Bar']).to eq 'value'
      expect(headers['bar_bar']).to eq 'value'
    end

    it "converts header values to strings" do
      expect(@request.make_headers('A' => 1)['A']).to eq '1'
    end
  end

  it "executes by constructing the Net::HTTP object, headers, and payload and calling transmit" do
    expect(@request).to receive(:parse_url_with_auth).with('http://some/resource').and_return(@uri)
    klass = double("net:http class")
    expect(@request).to receive(:net_http_request_class).with(:put).and_return(klass)
    expect(klass).to receive(:new).and_return('result')
    expect(@request).to receive(:transmit).with(@uri, 'result', kind_of(RestClient::Payload::Base))
    @request.execute
  end

  it "IPv6: executes by constructing the Net::HTTP object, headers, and payload and calling transmit" do
    @request = RestClient::Request.new(:method => :put, :url => 'http://[::1]/some/resource', :payload => 'payload')
    klass = double("net:http class")
    expect(@request).to receive(:net_http_request_class).with(:put).and_return(klass)

    if RUBY_VERSION >= "2.0.0"
      expect(klass).to receive(:new).with(kind_of(URI), kind_of(Hash)).and_return('result')
    else
      expect(klass).to receive(:new).with(kind_of(String), kind_of(Hash)).and_return('result')
    end

    expect(@request).to receive(:transmit)
    @request.execute
  end

  it "transmits the request with Net::HTTP" do
    expect(@http).to receive(:request).with('req', 'payload')
    expect(@request).to receive(:process_result)
    @request.transmit(@uri, 'req', 'payload')
  end

  describe "payload" do
    it "sends nil payloads" do
      expect(@http).to receive(:request).with('req', nil)
      expect(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', nil)
    end

    it "passes non-hash payloads straight through" do
      expect(@request.process_payload("x")).to eq "x"
    end

    it "converts a hash payload to urlencoded data" do
      expect(@request.process_payload(:a => 'b c+d')).to eq "a=b%20c%2Bd"
    end

    it "accepts nested hashes in payload" do
      payload = @request.process_payload(:user => { :name => 'joe', :location => { :country => 'USA', :state => 'CA' }})
      expect(payload).to include('user[name]=joe')
      expect(payload).to include('user[location][country]=USA')
      expect(payload).to include('user[location][state]=CA')
    end
  end

  it "set urlencoded content_type header on hash payloads" do
    @request.process_payload(:a => 1)
    expect(@request.headers[:content_type]).to eq 'application/x-www-form-urlencoded'
  end

  describe "credentials" do
    it "sets up the credentials prior to the request" do
      allow(@http).to receive(:request)

      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)

      allow(@request).to receive(:user).and_return('joe')
      allow(@request).to receive(:password).and_return('mypass')
      expect(@request).to receive(:setup_credentials).with('req')

      @request.transmit(@uri, 'req', nil)
    end

    it "does not attempt to send any credentials if user is nil" do
      allow(@request).to receive(:user).and_return(nil)
      req = double("request")
      expect(req).not_to receive(:basic_auth)
      @request.setup_credentials(req)
    end

    it "setup credentials when there's a user" do
      allow(@request).to receive(:user).and_return('joe')
      allow(@request).to receive(:password).and_return('mypass')
      req = double("request")
      expect(req).to receive(:basic_auth).with('joe', 'mypass')
      @request.setup_credentials(req)
    end
  end

  it "catches EOFError and shows the more informative ServerBrokeConnection" do
    allow(@http).to receive(:request).and_raise(EOFError)
    expect { @request.transmit(@uri, 'req', nil) }.to raise_error(RestClient::ServerBrokeConnection)
  end

  it "catches OpenSSL::SSL::SSLError and raise it back without more informative message" do
    allow(@http).to receive(:request).and_raise(OpenSSL::SSL::SSLError)
    expect { @request.transmit(@uri, 'req', nil) }.to raise_error(OpenSSL::SSL::SSLError)
  end

  it "catches Timeout::Error and raise the more informative RequestTimeout" do
    allow(@http).to receive(:request).and_raise(Timeout::Error)
    expect { @request.transmit(@uri, 'req', nil) }.to raise_error(RestClient::RequestTimeout)
  end

  it "catches Timeout::Error and raise the more informative RequestTimeout" do
    allow(@http).to receive(:request).and_raise(Errno::ETIMEDOUT)
    expect { @request.transmit(@uri, 'req', nil) }.to raise_error(RestClient::RequestTimeout)
  end

  it "class method execute wraps constructor" do
    req = double("rest request")
    expect(RestClient::Request).to receive(:new).with(1 => 2).and_return(req)
    expect(req).to receive(:execute)
    RestClient::Request.execute(1 => 2)
  end

  describe "exception" do
    it "raises Unauthorized when the response is 401" do
      res = double('response', :code => '401', :[] => ['content-encoding' => ''], :body => '' )
      expect { @request.process_result(res) }.to raise_error(RestClient::Unauthorized)
    end

    it "raises ResourceNotFound when the response is 404" do
      res = double('response', :code => '404', :[] => ['content-encoding' => ''], :body => '' )
      expect { @request.process_result(res) }.to raise_error(RestClient::ResourceNotFound)
    end

    it "raises RequestFailed otherwise" do
      res = double('response', :code => '500', :[] => ['content-encoding' => ''], :body => '' )
      expect { @request.process_result(res) }.to raise_error(RestClient::InternalServerError)
    end
  end

  describe "block usage" do
    it "returns what asked to" do
      res = double('response', :code => '401', :[] => ['content-encoding' => ''], :body => '' )
      expect(@request.process_result(res){|response, request| "foo"}).to eq "foo"
    end
  end

  describe "proxy" do
    it "creates a proxy class if a proxy url is given" do
      allow(RestClient).to receive(:proxy).and_return("http://example.com/")
      expect(@request.net_http_class.proxy_class?).to be_truthy
    end

    it "creates a proxy class with the correct address if a IPv6 proxy url is given" do
      allow(RestClient).to receive(:proxy).and_return("http://[::1]/")
      expect(@request.net_http_class.proxy_address).to eq("::1")
    end

    it "creates a non-proxy class if a proxy url is not given" do
      expect(@request.net_http_class.proxy_class?).to be_falsey
    end
  end


  describe "logging" do
    it "logs a get request" do
      log = RestClient.log = []
      RestClient::Request.new(:method => :get, :url => 'http://url', :headers => {:user_agent => 'rest-client'}).log_request
      expect(log[0]).to eq %Q{RestClient.get "http://url", "Accept"=>"*/*", "Accept-Encoding"=>"gzip, deflate", "User-Agent"=>"rest-client"\n}
    end

    it "logs a post request with a small payload" do
      log = RestClient.log = []
      RestClient::Request.new(:method => :post, :url => 'http://url', :payload => 'foo', :headers => {:user_agent => 'rest-client'}).log_request
      expect(log[0]).to eq %Q{RestClient.post "http://url", "foo", "Accept"=>"*/*", "Accept-Encoding"=>"gzip, deflate", "Content-Length"=>"3", "User-Agent"=>"rest-client"\n}
    end

    it "logs a post request with a large payload" do
      log = RestClient.log = []
      RestClient::Request.new(:method => :post, :url => 'http://url', :payload => ('x' * 1000), :headers => {:user_agent => 'rest-client'}).log_request
      expect(log[0]).to eq %Q{RestClient.post "http://url", 1000 byte(s) length, "Accept"=>"*/*", "Accept-Encoding"=>"gzip, deflate", "Content-Length"=>"1000", "User-Agent"=>"rest-client"\n}
    end

    it "logs input headers as a hash" do
      log = RestClient.log = []
      RestClient::Request.new(:method => :get, :url => 'http://url', :headers => { :accept => 'text/plain', :user_agent => 'rest-client' }).log_request
      expect(log[0]).to eq %Q{RestClient.get "http://url", "Accept"=>"text/plain", "Accept-Encoding"=>"gzip, deflate", "User-Agent"=>"rest-client"\n}
    end

    it "logs a response including the status code, content type, and result body size in bytes" do
      log = RestClient.log = []
      res = double('result', :code => '200', :class => Net::HTTPOK, :body => 'abcd')
      allow(res).to receive(:[]).with('Content-type').and_return('text/html')
      @request.log_response res
      expect(log[0]).to eq "# => 200 OK | text/html 4 bytes\n"
    end

    it "logs a response with a nil Content-type" do
      log = RestClient.log = []
      res = double('result', :code => '200', :class => Net::HTTPOK, :body => 'abcd')
      allow(res).to receive(:[]).with('Content-type').and_return(nil)
      @request.log_response res
      expect(log[0]).to eq "# => 200 OK |  4 bytes\n"
    end

    it "logs a response with a nil body" do
      log = RestClient.log = []
      res = double('result', :code => '200', :class => Net::HTTPOK, :body => nil)
      allow(res).to receive(:[]).with('Content-type').and_return('text/html; charset=utf-8')
      @request.log_response res
      expect(log[0]).to eq "# => 200 OK | text/html 0 bytes\n"
    end
  end

  it "strips the charset from the response content type" do
    log = RestClient.log = []
    res = double('result', :code => '200', :class => Net::HTTPOK, :body => 'abcd')
    allow(res).to receive(:[]).with('Content-type').and_return('text/html; charset=utf-8')
    @request.log_response res
    expect(log[0]).to eq "# => 200 OK | text/html 4 bytes\n"
  end

  describe "timeout" do
    it "does not set timeouts if not specified" do
      @request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload')
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)

      expect(@net).not_to receive(:read_timeout=)
      expect(@net).not_to receive(:open_timeout=)

      @request.transmit(@uri, 'req', nil)
    end

    it "set read_timeout" do
      @request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload', :timeout => 123)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)

      expect(@net).to receive(:read_timeout=).with(123)

      @request.transmit(@uri, 'req', nil)
    end

    it "set open_timeout" do
      @request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload', :open_timeout => 123)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)

      expect(@net).to receive(:open_timeout=).with(123)

      @request.transmit(@uri, 'req', nil)
    end

    it "disable timeout by setting it to nil" do
      @request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload', :timeout => nil, :open_timeout => nil)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)

      expect(@net).to receive(:read_timeout=).with(nil)
      expect(@net).to receive(:open_timeout=).with(nil)

      @request.transmit(@uri, 'req', nil)
    end

    it "deprecated: disable timeout by setting it to -1" do
      @request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload', :timeout => -1, :open_timeout => -1)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)

      expect(@request).to receive(:warn)
      expect(@net).to receive(:read_timeout=).with(nil)

      expect(@request).to receive(:warn)
      expect(@net).to receive(:open_timeout=).with(nil)

      @request.transmit(@uri, 'req', nil)
    end
  end

  describe "ssl" do
    it "uses SSL when the URI refers to a https address" do
      allow(@uri).to receive(:is_a?).with(URI::HTTPS).and_return(true)
      expect(@net).to receive(:use_ssl=).with(true)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should default to verifying ssl certificates" do
      expect(@request.verify_ssl).to eq OpenSSL::SSL::VERIFY_PEER
    end

    it "should have expected values for VERIFY_PEER and VERIFY_NONE" do
      expect(OpenSSL::SSL::VERIFY_NONE).to eq(0)
      expect(OpenSSL::SSL::VERIFY_PEER).to eq(1)
    end

    it "should set net.verify_mode to OpenSSL::SSL::VERIFY_NONE if verify_ssl is false" do
      @request = RestClient::Request.new(:method => :put, :verify_ssl => false, :url => 'http://some/resource', :payload => 'payload')
      expect(@net).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set net.verify_mode to OpenSSL::SSL::VERIFY_NONE if verify_ssl is true" do
      @request = RestClient::Request.new(:method => :put, :url => 'https://some/resource', :payload => 'payload', :verify_ssl => true)
      expect(@net).not_to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set net.verify_mode to OpenSSL::SSL::VERIFY_PEER if verify_ssl is true" do
      @request = RestClient::Request.new(:method => :put, :url => 'https://some/resource', :payload => 'payload', :verify_ssl => true)
      expect(@net).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set net.verify_mode to OpenSSL::SSL::VERIFY_PEER if verify_ssl is not given" do
      @request = RestClient::Request.new(:method => :put, :url => 'https://some/resource', :payload => 'payload')
      expect(@net).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set net.verify_mode to the passed value if verify_ssl is an OpenSSL constant" do
      mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
      @request = RestClient::Request.new( :method => :put,
                                          :url => 'https://some/resource',
                                          :payload => 'payload',
                                          :verify_ssl => mode )
      expect(@net).to receive(:verify_mode=).with(mode)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should default to not having an ssl_client_cert" do
      expect(@request.ssl_client_cert).to be(nil)
    end

    it "should set the ssl_version if provided" do
      @request = RestClient::Request.new(
        :method => :put,
        :url => 'https://some/resource',
        :payload => 'payload',
        :ssl_version => "TLSv1"
      )
      expect(@net).to receive(:ssl_version=).with("TLSv1")
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_version if not provided" do
      @request = RestClient::Request.new(
        :method => :put,
        :url => 'https://some/resource',
        :payload => 'payload'
      )
      expect(@net).not_to receive(:ssl_version=).with("TLSv1")
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set the ssl_ciphers if provided" do
      ciphers = 'AESGCM:HIGH:!aNULL:!eNULL:RC4+RSA'
      @request = RestClient::Request.new(
        :method => :put,
        :url => 'https://some/resource',
        :payload => 'payload',
        :ssl_ciphers => ciphers
      )
      expect(@net).to receive(:ciphers=).with(ciphers)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_ciphers if set to nil" do
      @request = RestClient::Request.new(
        :method => :put,
        :url => 'https://some/resource',
        :payload => 'payload',
        :ssl_ciphers => nil,
      )
      expect(@net).not_to receive(:ciphers=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should override ssl_ciphers with better defaults with weak default ciphers" do
      stub_const(
        '::OpenSSL::SSL::SSLContext::DEFAULT_PARAMS',
        {
          :ssl_version=>"SSLv23",
          :verify_mode=>1,
          :ciphers=>"ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM:+LOW",
          :options=>-2147480577,
        }
      )

      @request = RestClient::Request.new(
        :method => :put,
        :url => 'https://some/resource',
        :payload => 'payload',
      )

      expect(@net).to receive(:ciphers=).with(RestClient::Request::DefaultCiphers)

      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not override ssl_ciphers with better defaults with different default ciphers" do
      stub_const(
        '::OpenSSL::SSL::SSLContext::DEFAULT_PARAMS',
        {
          :ssl_version=>"SSLv23",
          :verify_mode=>1,
          :ciphers=>"HIGH:!aNULL:!eNULL:!EXPORT:!LOW:!MEDIUM:!SSLv2",
          :options=>-2147480577,
        }
      )

      @request = RestClient::Request.new(
        :method => :put,
        :url => 'https://some/resource',
        :payload => 'payload',
      )

      expect(@net).not_to receive(:ciphers=)

      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set the ssl_client_cert if provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_client_cert => "whatsupdoc!"
      )
      expect(@net).to receive(:cert=).with("whatsupdoc!")
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_client_cert if it is not provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload'
      )
      expect(@net).not_to receive(:cert=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should default to not having an ssl_client_key" do
      expect(@request.ssl_client_key).to be(nil)
    end

    it "should set the ssl_client_key if provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_client_key => "whatsupdoc!"
      )
      expect(@net).to receive(:key=).with("whatsupdoc!")
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_client_key if it is not provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload'
      )
      expect(@net).not_to receive(:key=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should default to not having an ssl_ca_file" do
      expect(@request.ssl_ca_file).to be(nil)
    end

    it "should set the ssl_ca_file if provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_ca_file => "Certificate Authority File"
      )
      expect(@net).to receive(:ca_file=).with("Certificate Authority File")
      expect(@net).not_to receive(:cert_store=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_ca_file if it is not provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload'
      )
      expect(@net).not_to receive(:ca_file=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should default to not having an ssl_ca_path" do
      expect(@request.ssl_ca_path).to be(nil)
    end

    it "should set the ssl_ca_path if provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_ca_path => "Certificate Authority Path"
      )
      expect(@net).to receive(:ca_path=).with("Certificate Authority Path")
      expect(@net).not_to receive(:cert_store=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_ca_path if it is not provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload'
      )
      expect(@net).not_to receive(:ca_path=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set the ssl_cert_store if provided" do
      store = OpenSSL::X509::Store.new
      store.set_default_paths

      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_cert_store => store
      )
      expect(@net).to receive(:cert_store=).with(store)
      expect(@net).not_to receive(:ca_path=)
      expect(@net).not_to receive(:ca_file=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should by default set the ssl_cert_store if no CA info is provided" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload'
      )
      expect(@net).to receive(:cert_store=)
      expect(@net).not_to receive(:ca_path=)
      expect(@net).not_to receive(:ca_file=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_cert_store if it is set falsy" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_cert_store => nil,
      )
      expect(@net).not_to receive(:cert_store=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should not set the ssl_verify_callback by default" do
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
      )
      expect(@net).not_to receive(:verify_callback=)
      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    it "should set the ssl_verify_callback if passed" do
      callback = lambda {}
      @request = RestClient::Request.new(
              :method => :put,
              :url => 'https://some/resource',
              :payload => 'payload',
              :ssl_verify_callback => callback,
      )
      expect(@net).to receive(:verify_callback=).with(callback)

      # we'll read cert_store on jruby
      # https://github.com/jruby/jruby/issues/597
      if RestClient::Platform.jruby?
        allow(@net).to receive(:cert_store)
      end

      allow(@http).to receive(:request)
      allow(@request).to receive(:process_result)
      allow(@request).to receive(:response_log)
      @request.transmit(@uri, 'req', 'payload')
    end

    # </ssl>
  end

  it "should still return a response object for 204 No Content responses" do
    @request = RestClient::Request.new(
            :method => :put,
            :url => 'https://some/resource',
            :payload => 'payload'
    )
    net_http_res = Net::HTTPNoContent.new("", "204", "No Content")
    allow(net_http_res).to receive(:read_body).and_return(nil)
    expect(@http).to receive(:request).and_return(@request.fetch_body(net_http_res))
    response = @request.transmit(@uri, 'req', 'payload')
    expect(response).not_to be_nil
    expect(response.code).to eq 204
  end

  describe "raw response" do
    it "should read the response into a binary-mode tempfile" do
      @request = RestClient::Request.new(:method => "get", :url => "example.com", :raw_response => true)

      tempfile = double("tempfile")
      expect(tempfile).to receive(:binmode)
      allow(tempfile).to receive(:open)
      allow(tempfile).to receive(:close)
      expect(Tempfile).to receive(:new).with("rest-client").and_return(tempfile)

      net_http_res = Net::HTTPOK.new(nil, "200", "body")
      allow(net_http_res).to receive(:read_body).and_return("body")
      @request.fetch_body(net_http_res)
    end
  end
end
