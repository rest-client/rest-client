require File.dirname(__FILE__) + '/base'

describe RestClient do
	context "public API" do
		it "GET" do
			RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => {})
			RestClient.get('http://some/resource')
		end

		it "POST" do
			RestClient::Request.should_receive(:execute).with(:method => :post, :url => 'http://some/resource', :payload => 'payload', :headers => {})
			RestClient.post('http://some/resource', 'payload')
		end

		it "PUT" do
			RestClient::Request.should_receive(:execute).with(:method => :put, :url => 'http://some/resource', :payload => 'payload', :headers => {})
			RestClient.put('http://some/resource', 'payload')
		end

		it "DELETE" do
			RestClient::Request.should_receive(:execute).with(:method => :delete, :url => 'http://some/resource', :headers => {})
			RestClient.delete('http://some/resource')
		end
	end

	context RestClient::Request do
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
		end

		it "requests xml mimetype" do
			RestClient::Request.default_headers[:accept].should == 'application/xml'
		end

		it "processes a successful result" do
			res = mock("result")
			res.stub!(:code).and_return("200")
			res.stub!(:body).and_return('body')
			@request.process_result(res).should == 'body'
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

		it "determines the Net::HTTP class to instantiate by the method name" do
			@request.net_http_class(:put).should == Net::HTTP::Put
		end

		it "merges user headers with the default headers" do
			RestClient::Request.should_receive(:default_headers).and_return({ '1' => '2' })
			@request.make_headers('3' => '4').should == { '1' => '2', '3' => '4' }
		end

		it "prefers the user header when the same header exists in the defaults" do
			RestClient::Request.should_receive(:default_headers).and_return({ '1' => '2' })
			@request.make_headers('1' => '3').should == { '1' => '3' }
		end

		it "converts header symbols from :content_type to 'Content-type'" do
			RestClient::Request.should_receive(:default_headers).and_return({})
			@request.make_headers(:content_type => 'abc').should == { 'Content-type' => 'abc' }
		end

		it "executes by constructing the Net::HTTP object, headers, and payload and calling transmit" do
			@request.should_receive(:parse_url_with_auth).with('http://some/resource').and_return(@uri)
			klass = mock("net:http class")
			@request.should_receive(:net_http_class).with(:put).and_return(klass)
			klass.should_receive(:new).and_return('result')
			@request.should_receive(:transmit).with(@uri, 'result', 'payload')
			@request.execute_inner
		end

		it "transmits the request with Net::HTTP" do
			@http.should_receive(:request).with('req', 'payload')
			@request.should_receive(:process_result)
			@request.transmit(@uri, 'req', 'payload')
		end

		it "uses SSL when the URI refers to a https address" do
			@uri.stub!(:is_a?).with(URI::HTTPS).and_return(true)
			@net.should_receive(:use_ssl=).with(true)
			@http.stub!(:request)
			@request.stub!(:process_result)
			@request.transmit(@uri, 'req', 'payload')
		end

		it "doesn't send nil payloads" do
			@http.should_receive(:request).with('req', '')
			@request.should_receive(:process_result)
			@request.transmit(@uri, 'req', nil)
		end

		it "passes non-hash payloads straight through" do
			@request.process_payload("x").should == "x"
		end

		it "converts a hash payload to urlencoded data" do
			@request.process_payload(:a => 'b c+d').should == "a=b%20c%2Bd"
		end

		it "set urlencoded content_type header on hash payloads" do
			@request.process_payload(:a => 1)
			@request.headers[:content_type].should == 'application/x-www-form-urlencoded'
		end

		it "sets up the credentials prior to the request" do
			@http.stub!(:request)
			@request.stub!(:process_result)

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
			lambda { @request.process_result(res) }.should raise_error(RestClient::Redirect, 'http://new/resource')
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
	end
end
