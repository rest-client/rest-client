require File.dirname(__FILE__) + '/base'

describe RestClient do
	context "public API" do
		before do
			@request = mock("restclient request")
		end

		it "GET" do
			RestClient::Request.should_receive(:new).with(:get, 'http://some/resource', nil, {}).and_return(@request)
			@request.should_receive(:execute)
			RestClient.get('http://some/resource')
		end

		it "POST" do
			RestClient::Request.should_receive(:new).with(:post, 'http://some/resource', 'payload', {}).and_return(@request)
			@request.should_receive(:execute)
			RestClient.post('http://some/resource', 'payload')
		end

		it "PUT" do
			RestClient::Request.should_receive(:new).with(:put, 'http://some/resource', 'payload', {}).and_return(@request)
			@request.should_receive(:execute)
			RestClient.put('http://some/resource', 'payload')
		end

		it "DELETE" do
			RestClient::Request.should_receive(:new).with(:delete, 'http://some/resource', nil, {}).and_return(@request)
			@request.should_receive(:execute)
			RestClient.delete('http://some/resource')
		end
	end

	context RestClient::Request do
		before do
			@request = RestClient::Request.new(:put, 'http://some/resource', 'payload', {})

			@uri = mock("uri")
			@uri.stub!(:path).and_return('/resource')
			@uri.stub!(:host).and_return('some')
			@uri.stub!(:port).and_return(80)
		end

		it "requests xml mimetype" do
			@request.default_headers[:accept].should == 'application/xml'
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

		it "determines the Net::HTTP class to instantiate by the method name" do
			@request.net_http_class(:put).should == Net::HTTP::Put
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

		it "executes by constructing the Net::HTTP object, headers, and payload and calling transmit" do
			@request.should_receive(:parse_url).with('http://some/resource').and_return(@uri)
			klass = mock("net:http class")
			@request.should_receive(:net_http_class).with(:put).and_return(klass)
			klass.should_receive(:new).and_return('result')
			@request.should_receive(:transmit).with(@uri, 'result', 'payload')
			@request.execute_inner
		end

		it "transmits the request with Net::HTTP" do
			http = mock("net::http connection")
			Net::HTTP.should_receive(:start).and_yield(http)
			http.should_receive(:request).with('req', 'payload')
			@request.should_receive(:process_result)
			@request.transmit(@uri, 'req', 'payload')
		end

		it "doesn't send nil payloads" do
			http = mock("net::http connection")
			Net::HTTP.should_receive(:start).and_yield(http)
			http.should_receive(:request).with('req', '')
			@request.should_receive(:process_result)
			@request.transmit(@uri, 'req', nil)
		end

		it "execute calls execute_inner" do
			@request.should_receive(:execute_inner)
			@request.execute
		end
	end
end
