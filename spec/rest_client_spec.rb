require File.dirname(__FILE__) + '/base'

describe RestClient do
	context "public API" do
		it "GET" do
			RestClient.should_receive(:do_request).with(:get, 'http://some/resource')
			RestClient.get('http://some/resource')
		end

		it "POST" do
			RestClient.should_receive(:do_request).with(:post, 'http://some/resource', 'payload')
			RestClient.post('http://some/resource', 'payload')
		end

		it "PUT" do
			RestClient.should_receive(:do_request).with(:put, 'http://some/resource', 'payload')
			RestClient.put('http://some/resource', 'payload')
		end

		it "DELETE" do
			RestClient.should_receive(:do_request).with(:delete, 'http://some/resource')
			RestClient.delete('http://some/resource')
		end
	end

	context "internal support methods" do
		it "requests xml mimetype" do
			RestClient.headers['Accept'].should == 'application/xml'
		end

		it "converts an xml document" do
			REXML::Document.should_receive(:new).with('body')
			RestClient.xml('body')
		end

		it "processes a successful result" do
			res = mock("result")
			res.stub!(:code).and_return("200")
			res.stub!(:body).and_return('body')
			RestClient.process_result(res).should == 'body'
		end

		it "parses a url into a URI object" do
			URI.should_receive(:parse).with('http://example.com/resource')
			RestClient.parse_url('http://example.com/resource')
		end

		it "adds http:// to the front of resources specified in the syntax example.com/resource" do
			URI.should_receive(:parse).with('http://example.com/resource')
			RestClient.parse_url('example.com/resource')
		end

		it "determines the Net::HTTP class to instantiate by the method name" do
			RestClient.net_http_class(:put).should == Net::HTTP::Put
		end
	end

	context "internal transmission methods" do
		before do
			@uri = mock("uri")
			@uri.stub!(:path).and_return('/resource')
			@uri.stub!(:host).and_return('some')
			@uri.stub!(:port).and_return(80)
		end

		it "does a request with an http method name passed in as a symbol" do
			RestClient.should_receive(:parse_url).with('http://some/resource').and_return(@uri)
			klass = mock("net:http class")
			RestClient.should_receive(:net_http_class).with(:put).and_return(klass)
			klass.should_receive(:new).with('/resource', RestClient.headers).and_return('result')
			RestClient.should_receive(:transmit).with(@uri, 'result', 'payload')
			RestClient.do_request_inner(:put, 'http://some/resource', 'payload')
		end

		it "transmits the request with Net::HTTP" do
			http = mock("net::http connection")
			Net::HTTP.should_receive(:start).and_yield(http)
			http.should_receive(:request).with('req', 'payload')
			RestClient.should_receive(:process_result)
			RestClient.transmit(@uri, 'req', 'payload')
		end

		it "doesn't send nil payloads" do
			http = mock("net::http connection")
			Net::HTTP.should_receive(:start).and_yield(http)
			http.should_receive(:request).with('req', '')
			RestClient.should_receive(:process_result)
			RestClient.transmit(@uri, 'req', nil)
		end

		it "do_request calls do_request_inner" do
			RestClient.should_receive(:do_request_inner).with(:get, 'http://some/where', 'payload')
			RestClient.do_request(:get, 'http://some/where', 'payload')
		end
	end
end
