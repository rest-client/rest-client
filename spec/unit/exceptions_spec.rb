require_relative '_lib'

describe RestClient2::Exception do
  it "returns a 'message' equal to the class name if the message is not set, because 'message' should not be nil" do
    e = RestClient2::Exception.new
    expect(e.message).to eq "RestClient2::Exception"
  end

  it "returns the 'message' that was set" do
    e = RestClient2::Exception.new
    message = "An explicitly set message"
    e.message = message
    expect(e.message).to eq message
  end

  it "sets the exception message to ErrorMessage" do
    expect(RestClient2::ResourceNotFound.new.message).to eq 'Not Found'
  end

  it "contains exceptions in RestClient2" do
    expect(RestClient2::Unauthorized.new).to be_a_kind_of(RestClient2::Exception)
    expect(RestClient2::ServerBrokeConnection.new).to be_a_kind_of(RestClient2::Exception)
  end
end

describe RestClient2::ServerBrokeConnection do
  it "should have a default message of 'Server broke connection'" do
    e = RestClient2::ServerBrokeConnection.new
    expect(e.message).to eq 'Server broke connection'
  end
end

describe RestClient2::RequestFailed do
  before do
    @response = double('HTTP Response', :code => '502')
  end

  it "stores the http response on the exception" do
    response = "response"
    begin
      raise RestClient2::RequestFailed, response
    rescue RestClient2::RequestFailed => e
      expect(e.response).to eq response
    end
  end

  it "http_code convenience method for fetching the code as an integer" do
    expect(RestClient2::RequestFailed.new(@response).http_code).to eq 502
  end

  it "http_body convenience method for fetching the body (decoding when necessary)" do
    expect(RestClient2::RequestFailed.new(@response).http_code).to eq 502
    expect(RestClient2::RequestFailed.new(@response).message).to eq 'HTTP status code 502'
  end

  it "shows the status code in the message" do
    expect(RestClient2::RequestFailed.new(@response).to_s).to match(/502/)
  end
end

describe RestClient2::ResourceNotFound do
  it "also has the http response attached" do
    response = "response"
    begin
      raise RestClient2::ResourceNotFound, response
    rescue RestClient2::ResourceNotFound => e
      expect(e.response).to eq response
    end
  end

  it 'stores the body on the response of the exception' do
    body = "body"
    stub_request(:get, "www.example.com").to_return(:body => body, :status => 404)
    begin
      RestClient2.get "www.example.com"
      raise
    rescue RestClient2::ResourceNotFound => e
      expect(e.response.body).to eq body
    end
  end
end

describe "backwards compatibility" do
  it 'aliases RestClient2::NotFound as ResourceNotFound' do
    expect(RestClient2::ResourceNotFound).to eq RestClient2::NotFound
  end

  it 'aliases old names for HTTP 413, 414, 416' do
    expect(RestClient2::RequestEntityTooLarge).to eq RestClient2::PayloadTooLarge
    expect(RestClient2::RequestURITooLong).to eq RestClient2::URITooLong
    expect(RestClient2::RequestedRangeNotSatisfiable).to eq RestClient2::RangeNotSatisfiable
  end

  it 'subclasses NotFound from RequestFailed, ExceptionWithResponse' do
    expect(RestClient2::NotFound).to be < RestClient2::RequestFailed
    expect(RestClient2::NotFound).to be < RestClient2::ExceptionWithResponse
  end

  it 'subclasses timeout from RestClient2::RequestTimeout, RequestFailed, EWR' do
    expect(RestClient2::Exceptions::OpenTimeout).to be < RestClient2::Exceptions::Timeout
    expect(RestClient2::Exceptions::ReadTimeout).to be < RestClient2::Exceptions::Timeout

    expect(RestClient2::Exceptions::Timeout).to be < RestClient2::RequestTimeout
    expect(RestClient2::Exceptions::Timeout).to be < RestClient2::RequestFailed
    expect(RestClient2::Exceptions::Timeout).to be < RestClient2::ExceptionWithResponse
  end

end
