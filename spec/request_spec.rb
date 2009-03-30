require File.dirname(__FILE__) + '/base'

describe RestClient::Request do
	before do
		@request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload')

		@uri = mock("uri")
		@uri.stub!(:request_uri).and_return('/resource')
		@uri.stub!(:host).and_return('some')
		@uri.stub!(:port).and_return(80)

		@net = mock("net::http base")
		@http = mock("net::http connection")
		Net::HTTP.stub!(:new).and_return(@net)
		@net.stub!(:start).and_yield(@http)
		@net.stub!(:use_ssl=)
		@net.stub!(:verify_mode=)
	end

	it "requests xml mimetype" do
		@request.default_headers[:accept].should == 'application/xml'
	end

	it "decodes an uncompressed result body by passing it straight through" do
		@request.decode(nil, 'xyz').should == 'xyz'
	end

	it "decodes a gzip body" do
		@request.decode('gzip', "\037\213\b\b\006'\252H\000\003t\000\313T\317UH\257\312,HM\341\002\000G\242(\r\v\000\000\000").should == "i'm gziped\n"
	end

	it "ingores gzip for empty bodies" do
		@request.decode('gzip', '').should be_empty
	end

	it "decodes a deflated body" do
		@request.decode('deflate', "x\234+\316\317MUHIM\313I,IMQ(I\255(\001\000A\223\006\363").should == "some deflated text"
	end

	it "processes a successful result" do
		res = mock("result")
		res.stub!(:code).and_return("200")
		res.stub!(:body).and_return('body')
		res.stub!(:[]).with('content-encoding').and_return(nil)
		@request.process_result(res).should == 'body'
	end

	it "doesn't classify successful requests as failed" do
		203.upto(206) do |code|
			res = mock("result")
			res.stub!(:code).and_return(code.to_s)
			res.stub!(:body).and_return("")
			res.stub!(:[]).with('content-encoding').and_return(nil)
			@request.process_result(res).should be_empty
		end
	end

	it "parses a url into a URI object" do
		URI.should_receive(:parse).with('http://example.com/resource')
		@request.parse_url('http://example.com/resource')
	end

	it "adds http:// to the front of resources specified in the syntax example.com/resource" do
		URI.should_receive(:parse).with('http://example.com/resource')
		@request.parse_url('example.com/resource')
	end

	it "extracts the username and password when parsing http://user:password@example.com/" do
		URI.stub!(:parse).and_return(mock('uri', :user => 'joe', :password => 'pass1'))
		@request.parse_url_with_auth('http://joe:pass1@example.com/resource')
		@request.user.should == 'joe'
		@request.password.should == 'pass1'
	end

	it "doesn't overwrite user and password (which may have already been set by the Resource constructor) if there is no user/password in the url" do
		URI.stub!(:parse).and_return(mock('uri', :user => nil, :password => nil))
		@request = RestClient::Request.new(:method => 'get', :url => 'example.com', :user => 'beth', :password => 'pass2')
		@request.parse_url_with_auth('http://example.com/resource')
		@request.user.should == 'beth'
		@request.password.should == 'pass2'
	end

	it "correctly formats cookies provided to the constructor" do
		URI.stub!(:parse).and_return(mock('uri', :user => nil, :password => nil))
		@request = RestClient::Request.new(:method => 'get', :url => 'example.com', :cookies => {:session_id => '1' })
		@request.should_receive(:default_headers).and_return({'foo' => 'bar'})
		headers = @request.make_headers({}).should == { 'Foo' => 'bar', 'Cookie' => 'session_id=1'}
	end

	it "determines the Net::HTTP class to instantiate by the method name" do
		@request.net_http_request_class(:put).should == Net::HTTP::Put
	end

	it "merges user headers with the default headers" do
		@request.should_receive(:default_headers).and_return({ '1' => '2' })
		@request.make_headers('3' => '4').should == { '1' => '2', '3' => '4' }
	end

	it "prefers the user header when the same header exists in the defaults" do
		@request.should_receive(:default_headers).and_return({ '1' => '2' })
		@request.make_headers('1' => '3').should == { '1' => '3' }
	end

	it "converts header symbols from :content_type to 'Content-type'" do
		@request.should_receive(:default_headers).and_return({})
		@request.make_headers(:content_type => 'abc').should == { 'Content-type' => 'abc' }
	end

	it "converts header values to strings" do
		@request.make_headers('A' => 1)['A'].should == '1'
	end

	it "executes by constructing the Net::HTTP object, headers, and payload and calling transmit" do
		@request.should_receive(:parse_url_with_auth).with('http://some/resource').and_return(@uri)
		klass = mock("net:http class")
		@request.should_receive(:net_http_request_class).with(:put).and_return(klass)
		klass.should_receive(:new).and_return('result')
		@request.should_receive(:transmit).with(@uri, 'result', 'payload')
		@request.execute_inner
	end

	it "transmits the request with Net::HTTP" do
		@http.should_receive(:request).with('req', 'payload')
		@request.should_receive(:process_result)
		@request.should_receive(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "uses SSL when the URI refers to a https address" do
		@uri.stub!(:is_a?).with(URI::HTTPS).and_return(true)
		@net.should_receive(:use_ssl=).with(true)
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "sends nil payloads" do
		@http.should_receive(:request).with('req', nil)
		@request.should_receive(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', nil)
	end

	it "passes non-hash payloads straight through" do
		@request.process_payload("x").should == "x"
	end

	it "converts a hash payload to urlencoded data" do
		@request.process_payload(:a => 'b c+d').should == "a=b%20c%2Bd"
	end

	it "accepts nested hashes in payload" do
		payload = @request.process_payload(:user => { :name => 'joe', :location => { :country => 'USA', :state => 'CA' }})
		payload.should include('user[name]=joe')
		payload.should include('user[location][country]=USA')
		payload.should include('user[location][state]=CA')
	end

	it "set urlencoded content_type header on hash payloads" do
		@request.process_payload(:a => 1)
		@request.headers[:content_type].should == 'application/x-www-form-urlencoded'
	end

	it "sets up the credentials prior to the request" do
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)

		@request.stub!(:user).and_return('joe')
		@request.stub!(:password).and_return('mypass')
		@request.should_receive(:setup_credentials).with('req')

		@request.transmit(@uri, 'req', nil)
	end

	it "does not attempt to send any credentials if user is nil" do
		@request.stub!(:user).and_return(nil)
		req = mock("request")
		req.should_not_receive(:basic_auth)
		@request.setup_credentials(req)
	end

	it "setup credentials when there's a user" do
		@request.stub!(:user).and_return('joe')
		@request.stub!(:password).and_return('mypass')
		req = mock("request")
		req.should_receive(:basic_auth).with('joe', 'mypass')
		@request.setup_credentials(req)
	end

	it "catches EOFError and shows the more informative ServerBrokeConnection" do
		@http.stub!(:request).and_raise(EOFError)
		lambda { @request.transmit(@uri, 'req', nil) }.should raise_error(RestClient::ServerBrokeConnection)
	end

	it "execute calls execute_inner" do
		@request.should_receive(:execute_inner)
		@request.execute
	end

	it "class method execute wraps constructor" do
		req = mock("rest request")
		RestClient::Request.should_receive(:new).with(1 => 2).and_return(req)
		req.should_receive(:execute)
		RestClient::Request.execute(1 => 2)
	end

	it "raises a Redirect with the new location when the response is in the 30x range" do
		res = mock('response', :code => '301', :header => { 'Location' => 'http://new/resource' })
		lambda { @request.process_result(res) }.should raise_error(RestClient::Redirect) { |e| e.url.should == 'http://new/resource'}
	end

	it "handles redirects with relative paths" do
		res = mock('response', :code => '301', :header => { 'Location' => 'index' })
		lambda { @request.process_result(res) }.should raise_error(RestClient::Redirect) { |e| e.url.should == 'http://some/index' }
	end

	it "handles redirects with absolute paths" do
		@request.instance_variable_set('@url', 'http://some/place/else')
		res = mock('response', :code => '301', :header => { 'Location' => '/index' })
		lambda { @request.process_result(res) }.should raise_error(RestClient::Redirect) { |e| e.url.should == 'http://some/index' }
	end

	it "raises Unauthorized when the response is 401" do
		res = mock('response', :code => '401')
		lambda { @request.process_result(res) }.should raise_error(RestClient::Unauthorized)
	end

	it "raises ResourceNotFound when the response is 404" do
		res = mock('response', :code => '404')
		lambda { @request.process_result(res) }.should raise_error(RestClient::ResourceNotFound)
	end

	it "raises RequestFailed otherwise" do
		res = mock('response', :code => '500')
		lambda { @request.process_result(res) }.should raise_error(RestClient::RequestFailed)
	end

	it "creates a proxy class if a proxy url is given" do
		RestClient.stub!(:proxy).and_return("http://example.com/")
		@request.net_http_class.should include(Net::HTTP::ProxyDelta)
	end

	it "creates a non-proxy class if a proxy url is not given" do
		@request.net_http_class.should_not include(Net::HTTP::ProxyDelta)
	end

	it "logs a get request" do
		RestClient::Request.new(:method => :get, :url => 'http://url').request_log.should ==
		'RestClient.get "http://url"'
	end

	it "logs a post request with a small payload" do
		RestClient::Request.new(:method => :post, :url => 'http://url', :payload => 'foo').request_log.should ==
		'RestClient.post "http://url", "foo"'
	end

	it "logs a post request with a large payload" do
		RestClient::Request.new(:method => :post, :url => 'http://url', :payload => ('x' * 1000)).request_log.should ==
		'RestClient.post "http://url", "(1000 byte payload)"'
	end

	it "logs input headers as a hash" do
		RestClient::Request.new(:method => :get, :url => 'http://url', :headers => { :accept => 'text/plain' }).request_log.should ==
		'RestClient.get "http://url", :accept=>"text/plain"'
	end

	it "logs a response including the status code, content type, and result body size in bytes" do
		res = mock('result', :code => '200', :class => Net::HTTPOK, :body => 'abcd')
		res.stub!(:[]).with('Content-type').and_return('text/html')
		@request.response_log(res).should == "# => 200 OK | text/html 4 bytes"
	end

	it "logs a response with a nil Content-type" do
		res = mock('result', :code => '200', :class => Net::HTTPOK, :body => 'abcd')
		res.stub!(:[]).with('Content-type').and_return(nil)
		@request.response_log(res).should == "# => 200 OK |  4 bytes"
	end

	it "strips the charset from the response content type" do
		res = mock('result', :code => '200', :class => Net::HTTPOK, :body => 'abcd')
		res.stub!(:[]).with('Content-type').and_return('text/html; charset=utf-8')
		@request.response_log(res).should == "# => 200 OK | text/html 4 bytes"
	end

	it "displays the log to stdout" do
		RestClient.stub!(:log).and_return('stdout')
		STDOUT.should_receive(:puts).with('xyz')
		@request.display_log('xyz')
	end

	it "displays the log to stderr" do
		RestClient.stub!(:log).and_return('stderr')
		STDERR.should_receive(:puts).with('xyz')
		@request.display_log('xyz')
	end

	it "append the log to the requested filename" do
		RestClient.stub!(:log).and_return('/tmp/restclient.log')
		f = mock('file handle')
		File.should_receive(:open).with('/tmp/restclient.log', 'a').and_yield(f)
		f.should_receive(:puts).with('xyz')
		@request.display_log('xyz')
	end

	it "set read_timeout" do
		@request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload', :timeout => 123)
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)

		@net.should_receive(:read_timeout=).with(123)

		@request.transmit(@uri, 'req', nil)
	end

	it "set open_timeout" do
		@request = RestClient::Request.new(:method => :put, :url => 'http://some/resource', :payload => 'payload', :open_timeout => 123)
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)

		@net.should_receive(:open_timeout=).with(123)

		@request.transmit(@uri, 'req', nil)
	end

	it "should default to not verifying ssl certificates" do
		@request.verify_ssl.should == false
	end

	it "should set net.verify_mode to OpenSSL::SSL::VERIFY_NONE if verify_ssl is false" do
		@net.should_receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "should not set net.verify_mode to OpenSSL::SSL::VERIFY_NONE if verify_ssl is true" do
		@request = RestClient::Request.new(:method => :put, :url => 'https://some/resource', :payload => 'payload', :verify_ssl => true)
		@net.should_not_receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "should default to not having an ssl_client_cert" do
		@request.ssl_client_cert.should be(nil)
	end

	it "should set the ssl_client_cert if provided" do
		@request = RestClient::Request.new(
			:method => :put, 
			:url => 'https://some/resource', 
			:payload => 'payload',
			:ssl_client_cert => "whatsupdoc!"
		)
		@net.should_receive(:cert=).with("whatsupdoc!")
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "should not set the ssl_client_cert if it is not provided" do
		@request = RestClient::Request.new(
			:method => :put, 
			:url => 'https://some/resource', 
			:payload => 'payload'
		)
		@net.should_not_receive(:cert=).with("whatsupdoc!")
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "should default to not having an ssl_client_key" do
		@request.ssl_client_key.should be(nil)
	end

	it "should set the ssl_client_key if provided" do
		@request = RestClient::Request.new(
			:method => :put, 
			:url => 'https://some/resource', 
			:payload => 'payload',
			:ssl_client_key => "whatsupdoc!"
		)
		@net.should_receive(:key=).with("whatsupdoc!")
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "should not set the ssl_client_key if it is not provided" do
		@request = RestClient::Request.new(
			:method => :put, 
			:url => 'https://some/resource', 
			:payload => 'payload'
		)
		@net.should_not_receive(:key=).with("whatsupdoc!")
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end
	
	it "should default to not having an ssl_ca_file" do
		@request.ssl_ca_file.should be(nil)
	end

	it "should set the ssl_ca_file if provided" do
		@request = RestClient::Request.new(
			:method => :put, 
			:url => 'https://some/resource', 
			:payload => 'payload',
			:ssl_ca_file => "Certificate Authority File"
		)
		@net.should_receive(:ca_file=).with("Certificate Authority File")
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end

	it "should not set the ssl_ca_file if it is not provided" do
		@request = RestClient::Request.new(
			:method => :put, 
			:url => 'https://some/resource', 
			:payload => 'payload'
		)
		@net.should_not_receive(:ca_file=).with("Certificate Authority File")
		@http.stub!(:request)
		@request.stub!(:process_result)
		@request.stub!(:response_log)
		@request.transmit(@uri, 'req', 'payload')
	end
end
