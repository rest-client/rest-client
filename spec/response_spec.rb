require File.dirname(__FILE__) + '/base'

describe RestClient::Response do
	before do
		@net_http_res = mock('net http response')
		@response = RestClient::Response.new('abc', @net_http_res)
	end

	it "behaves like string" do
		@response.should == 'abc'
	end

	it "fetches the numeric response code" do
		@net_http_res.should_receive(:code).and_return('200')
		@response.code.should == 200
	end

	it "beautifies the headers by turning the keys to symbols" do
		h = RestClient::Response.beautify_headers('content-type' => [ 'x' ])
		h.keys.first.should == :content_type
	end

	it "beautifies the headers by turning the values to strings instead of one-element arrays" do
		h = RestClient::Response.beautify_headers('x' => [ 'text/html' ] )
		h.values.first.should == 'text/html'
	end

	it "fetches the headers" do
		@net_http_res.should_receive(:to_hash).and_return('content-type' => [ 'text/html' ])
		@response.headers.should == { :content_type => 'text/html' }
	end

  it "extracts cookies from response headers" do
    @net_http_res.should_receive(:to_hash).and_return('set-cookie' => ['session_id=1; path=/'])
    @response.cookies.should == { 'session_id' => '1' }
  end

	it "can access the net http result directly" do
		@response.net_http_res.should == @net_http_res
	end

	it "accepts nil strings and sets it to empty for the case of HEAD" do
		RestClient::Response.new(nil, @net_http_res).should == ""
	end
end
