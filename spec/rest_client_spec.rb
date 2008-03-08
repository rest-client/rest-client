require File.dirname(__FILE__) + '/base'

describe RestClient do
	context "internal methods" do
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
	end

	context "public API" do
		before do
			@uri = mock("uri")
			@uri.stub!(:path).and_return('/resource')
			RestClient.should_receive(:parse_url).with('http://some/resource').and_return(@uri)
		end

		it "GET url" do
			Net::HTTP::Get.should_receive(:new).with('/resource', RestClient.headers).and_return(:get)
			RestClient.should_receive(:transmit).with(@uri, :get)
			RestClient.get('http://some/resource')
		end

		it "POST url" do
			Net::HTTP::Post.should_receive(:new).with('/resource', RestClient.headers).and_return(:post)
			RestClient.should_receive(:transmit).with(@uri, :post, nil)
			RestClient.post('http://some/resource')
		end

		it "POST url, payload" do
			Net::HTTP::Post.should_receive(:new).with('/resource', RestClient.headers).and_return(:post)
			RestClient.should_receive(:transmit).with(@uri, :post, 'payload')
			RestClient.post('http://some/resource', 'payload')
		end

		it "PUT url" do
			Net::HTTP::Put.should_receive(:new).with('/resource', RestClient.headers).and_return(:put)
			RestClient.should_receive(:transmit).with(@uri, :put, nil)
			RestClient.put('http://some/resource')
		end

		it "PUT url, payload" do
			Net::HTTP::Put.should_receive(:new).with('/resource', RestClient.headers).and_return(:put)
			RestClient.should_receive(:transmit).with(@uri, :put, 'payload')
			RestClient.put('http://some/resource', 'payload')
		end

		it "DELETE url" do
			Net::HTTP::Delete.should_receive(:new).with('/resource', RestClient.headers).and_return(:delete)
			RestClient.should_receive(:transmit).with(@uri, :delete)
			RestClient.delete('http://some/resource')
		end
	end
end
