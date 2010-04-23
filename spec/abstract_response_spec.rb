require File.dirname(__FILE__) + '/base'

describe RestClient::AbstractResponse do

  class MyAbstractResponse

    include RestClient::AbstractResponse

    attr_accessor :size

    def initialize net_http_res, args
      @net_http_res = net_http_res
      @args = args
    end

  end

  before do
    @net_http_res = mock('net http response')
    @response = MyAbstractResponse.new(@net_http_res, {})
  end

  it "fetches the numeric response code" do
    @net_http_res.should_receive(:code).and_return('200')
    @response.code.should == 200
  end

  it "has a nice description" do
    @net_http_res.should_receive(:to_hash).and_return({'Content-Type' => ['application/pdf']})
    @net_http_res.should_receive(:code).and_return('200')
    @response.description == '200 OK | application/pdf  bytes\n'
  end

  it "beautifies the headers by turning the keys to symbols" do
    h = RestClient::AbstractResponse.beautify_headers('content-type' => [ 'x' ])
    h.keys.first.should == :content_type
  end

  it "beautifies the headers by turning the values to strings instead of one-element arrays" do
    h = RestClient::AbstractResponse.beautify_headers('x' => [ 'text/html' ] )
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
end
