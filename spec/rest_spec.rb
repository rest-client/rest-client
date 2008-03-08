require File.dirname(__FILE__) + '/base'

describe Rest do
	context "internal methods" do
		it "requests xml mimetype" do
			Rest.headers['Accept'].should == 'application/xml'
		end

		it "converts an xml document" do
			REXML::Document.should_receive(:new).with('body')
			Rest.xml('body')
		end

		it "processes a successful result" do
			res = mock("result")
			res.stub!(:code).and_return("200")
			res.stub!(:body).and_return('body')
			Rest.process_result(res).should == 'body'
		end

		it "parses a url into a URI object" do
			URI.should_receive(:parse).with('http://example.com/resource')
			Rest.parse_url('http://example.com/resource')
		end

		it "adds http:// to the front of resources specified in the syntax example.com/resource" do
			URI.should_receive(:parse).with('http://example.com/resource')
			Rest.parse_url('example.com/resource')
		end
	end

	context "public API" do
		before do
			@uri = mock("uri")
			@uri.stub!(:path).and_return('/resource')
			Rest.should_receive(:parse_url).with('http://some/resource').and_return(@uri)
		end

		it "GET url" do
			Net::HTTP::Get.should_receive(:new).with('/resource', Rest.headers).and_return(:get)
			Rest.should_receive(:transmit).with(@uri, :get)
			Rest.get('http://some/resource')
		end

		it "POST url" do
			Net::HTTP::Post.should_receive(:new).with('/resource', Rest.headers).and_return(:post)
			Rest.should_receive(:transmit).with(@uri, :post, nil)
			Rest.post('http://some/resource')
		end

		it "POST url, payload" do
			Net::HTTP::Post.should_receive(:new).with('/resource', Rest.headers).and_return(:post)
			Rest.should_receive(:transmit).with(@uri, :post, 'payload')
			Rest.post('http://some/resource', 'payload')
		end

		it "PUT url" do
			Net::HTTP::Put.should_receive(:new).with('/resource', Rest.headers).and_return(:put)
			Rest.should_receive(:transmit).with(@uri, :put, nil)
			Rest.put('http://some/resource')
		end

		it "PUT url, payload" do
			Net::HTTP::Put.should_receive(:new).with('/resource', Rest.headers).and_return(:put)
			Rest.should_receive(:transmit).with(@uri, :put, 'payload')
			Rest.put('http://some/resource', 'payload')
		end

		it "DELETE url" do
			Net::HTTP::Delete.should_receive(:new).with('/resource', Rest.headers).and_return(:delete)
			Rest.should_receive(:transmit).with(@uri, :delete)
			Rest.delete('http://some/resource')
		end
	end
end
