require_relative '_lib'

describe RestClient::AbstractResponse, :include_helpers do

  class MyAbstractResponse

    include RestClient::AbstractResponse

    attr_accessor :size

    def initialize net_http_res, request
      @net_http_res = net_http_res
      @request = request
    end

  end

  before do
    @net_http_res = double('net http response')
    @request = request_double(url: 'http://example.com', method: 'get')
    @response = MyAbstractResponse.new(@net_http_res, @request)
  end

  it "fetches the numeric response code" do
    @net_http_res.should_receive(:code).and_return('200')
    @response.code.should eq 200
  end

  it "has a nice description" do
    @net_http_res.should_receive(:to_hash).and_return({'Content-Type' => ['application/pdf']})
    @net_http_res.should_receive(:code).and_return('200')
    @response.description.should eq "200 OK | application/pdf  bytes\n"
  end

  describe '.beautify_headers' do
    it "beautifies the headers by turning the keys to symbols" do
      h = RestClient::AbstractResponse.beautify_headers('content-type' => [ 'x' ])
      h.keys.first.should eq :content_type
    end

    it "beautifies the headers by turning the values to strings instead of one-element arrays" do
      h = RestClient::AbstractResponse.beautify_headers('x' => [ 'text/html' ] )
      h.values.first.should eq 'text/html'
    end

    it 'joins multiple header values by comma' do
      RestClient::AbstractResponse.beautify_headers(
        {'My-Header' => ['one', 'two']}
      ).should eq({:my_header => 'one, two'})
    end

    it 'leaves set-cookie headers as array' do
      RestClient::AbstractResponse.beautify_headers(
        {'Set-Cookie' => ['cookie1=foo', 'cookie2=bar']}
      ).should eq({:set_cookie => ['cookie1=foo', 'cookie2=bar']})
    end
  end

  it "fetches the headers" do
    @net_http_res.should_receive(:to_hash).and_return('content-type' => [ 'text/html' ])
    @response.headers.should eq({ :content_type => 'text/html' })
  end

  it "extracts cookies from response headers" do
    @net_http_res.should_receive(:to_hash).and_return('set-cookie' => ['session_id=1; path=/'])
    @response.cookies.should eq({ 'session_id' => '1' })
  end

  it "extract strange cookies" do
    @net_http_res.should_receive(:to_hash).and_return('set-cookie' => ['session_id=ZJ/HQVH6YE+rVkTpn0zvTQ==; path=/'])
    @response.headers.should eq({:set_cookie => ['session_id=ZJ/HQVH6YE+rVkTpn0zvTQ==; path=/']})
    @response.cookies.should eq({ 'session_id' => 'ZJ/HQVH6YE+rVkTpn0zvTQ==' })
  end

  it "doesn't escape cookies" do
    @net_http_res.should_receive(:to_hash).and_return('set-cookie' => ['session_id=BAh7BzoNYXBwX25hbWUiEGFwcGxpY2F0aW9uOgpsb2dpbiIKYWRtaW4%3D%0A--08114ba654f17c04d20dcc5228ec672508f738ca; path=/'])
    @response.cookies.should eq({ 'session_id' => 'BAh7BzoNYXBwX25hbWUiEGFwcGxpY2F0aW9uOgpsb2dpbiIKYWRtaW4%3D%0A--08114ba654f17c04d20dcc5228ec672508f738ca' })
  end

  describe '.cookie_jar' do
    it 'extracts cookies into cookie jar' do
      @net_http_res.should_receive(:to_hash).and_return('set-cookie' => ['session_id=1; path=/'])
      @response.cookie_jar.should be_a HTTP::CookieJar

      cookie = @response.cookie_jar.cookies.first
      cookie.domain.should eq 'example.com'
      cookie.name.should eq 'session_id'
      cookie.value.should eq '1'
      cookie.path.should eq '/'
    end

    it 'handles cookies when URI scheme is implicit' do
      net_http_res = double('net http response')
      net_http_res.should_receive(:to_hash).and_return('set-cookie' => ['session_id=1; path=/'])
      request = double(url: 'example.com', uri: URI.parse('http://example.com'), method: 'get')
      response = MyAbstractResponse.new(net_http_res, request)
      response.cookie_jar.should be_a HTTP::CookieJar

      cookie = response.cookie_jar.cookies.first
      cookie.domain.should eq 'example.com'
      cookie.name.should eq 'session_id'
      cookie.value.should eq '1'
      cookie.path.should eq '/'
    end
  end

  it "can access the net http result directly" do
    @response.net_http_res.should eq @net_http_res
  end

  describe "#return!" do
    it "should return the response itself on 200-codes" do
      @net_http_res.should_receive(:code).and_return('200')
      @response.return!.should be_equal(@response)
    end

    it "should raise RequestFailed on unknown codes" do
      @net_http_res.should_receive(:code).and_return('1000')
      lambda { @response.return! }.should raise_error RestClient::RequestFailed
    end

    it "should raise an error on a redirection after non-GET/HEAD requests" do
      @net_http_res.should_receive(:code).and_return('301')
      @request.should_receive(:method).and_return('put')
      @response.should_not_receive(:follow_redirection)
      lambda { @response.return! }.should raise_error RestClient::RequestFailed
    end

    it "should follow 302 redirect" do
      @net_http_res.should_receive(:code).and_return('302')
      @response.should_receive(:follow_redirection).and_return('fake-redirection')
      @response.return!.should eq 'fake-redirection'
    end

    it "should gracefully handle 302 redirect with no location header" do
      @net_http_res = response_double(code: 302, location: nil)
      @request = request_double()
      @response = MyAbstractResponse.new(@net_http_res, @request)
      lambda { @response.return! }.should raise_error RestClient::Found
    end
  end
end
