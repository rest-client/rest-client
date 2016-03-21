require_relative './_lib'

describe RestClient::KeepAliveContext, :include_helpers do
  before do
    @context = RestClient::KeepAliveContext.new

    @response = double("restclient::response response")

    @http = double("net::http http")
    Net::HTTP.stub(:new).and_return(@http)

    @host_hash = {}

    @request = double("restclient::request request")
    RestClient::Request.stub(:new).and_return(@request)
    @request.stub(:http_object).and_return(@http)
    @request.stub(:execute).and_return(@response)
    @request.stub(:host_hash).and_return(@host_hash)
  end

  it "check args param contains :url" do
    lambda {
      @context.execute({})
    }.should raise_error ArgumentError, /\Amust pass url/
  end

  it "delegate to execute method of RestClient::Request instance" do
    @request.should_receive(:execute).and_return(@response)
    res = @context.execute({url: 'http://some/resource'})
    res.should eq @response
  end

  it "save the http object into host_hash member" do
    @context.host_hash.should_receive(:[]=).with('http://some:80', @http)
    @context.execute({url: 'http://some/resource'})
  end

  it "the second request to the same domain will pass the http object to the new request" do
    @context.execute({url: 'http://some/resource'})

    RestClient::Request.should_receive(:new).with({keep_alive: true, http_object: @http, url: 'http://some/other_resource'})
    @context.execute({url: 'http://some/other_resource'})
  end

end
