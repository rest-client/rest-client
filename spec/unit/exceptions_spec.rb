require_relative '_lib'

describe RestClient::Exception do
  let(:exception) { described_class.new }

  describe '#message' do
    subject { exception.message }

    context 'when it is not set' do
      it { is_expected.to eq 'RestClient::Exception' }
    end

    context 'when it is explicitly set' do
      before { exception.message = 'An explicitly set message' }
      it { is_expected.to eq 'An explicitly set message' }
    end
  end

  describe 'descendants' do
    [RestClient::Unauthorized, RestClient::ServerBrokeConnection].each do |klass|
      describe klass.name do
        subject { klass.new }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end

  describe '#request' do
    subject { exception.request }
    let(:request) { double 'HTTP Request' }
    it { is_expected.to be_nil }

    context 'when set explicitly' do
      let(:exception) { described_class.new nil, nil, request }
      it { is_expected.to eq request }
    end

    context 'when response is available' do
      let(:exception) { described_class.new double('HTTP Response', request: request) }
      it { is_expected.to eq request }
    end
  end
end

describe RestClient::ServerBrokeConnection do
  it "should have a default message of 'Server broke connection'" do
    e = RestClient::ServerBrokeConnection.new
    expect(e.message).to eq 'Server broke connection'
  end
end

describe RestClient::RequestFailed do
  let(:response) { double 'HTTP Response', code: '502', request: double('HTTP Request') }

  it "stores the http response on the exception" do
    begin
      raise RestClient::RequestFailed, response
    rescue RestClient::RequestFailed => e
      expect(e.response).to eq response
    end
  end

  it "http_code convenience method for fetching the code as an integer" do
    expect(RestClient::RequestFailed.new(response).http_code).to eq 502
  end

  it "http_body convenience method for fetching the body (decoding when necessary)" do
    expect(RestClient::RequestFailed.new(response).http_code).to eq 502
    expect(RestClient::RequestFailed.new(response).message).to eq 'HTTP status code 502'
  end

  it "shows the status code in the message" do
    expect(RestClient::RequestFailed.new(response).to_s).to match(/502/)
  end
end

describe RestClient::ResourceNotFound do
  let(:response) { double 'HTTP Response', code: '502', request: double('HTTP Request') }

  describe '#message' do
    subject { described_class.new.message }
    it { is_expected.to eq 'Not Found' }
  end

  it "also has the http response attached" do
    begin
      raise RestClient::ResourceNotFound, response
    rescue RestClient::ResourceNotFound => e
      expect(e.response).to eq response
    end
  end

  it 'stores the body on the response of the exception' do
    body = "body"
    stub_request(:get, "www.example.com").to_return(:body => body, :status => 404)
    begin
      RestClient.get "www.example.com"
      raise
    rescue RestClient::ResourceNotFound => e
      expect(e.response.body).to eq body
    end
  end
end

describe "backwards compatibility" do
  it 'aliases RestClient::NotFound as ResourceNotFound' do
    expect(RestClient::ResourceNotFound).to eq RestClient::NotFound
  end

  it 'aliases old names for HTTP 413, 414, 416' do
    expect(RestClient::RequestEntityTooLarge).to eq RestClient::PayloadTooLarge
    expect(RestClient::RequestURITooLong).to eq RestClient::URITooLong
    expect(RestClient::RequestedRangeNotSatisfiable).to eq RestClient::RangeNotSatisfiable
  end

  it 'subclasses NotFound from RequestFailed, ExceptionWithResponse' do
    expect(RestClient::NotFound).to be < RestClient::RequestFailed
    expect(RestClient::NotFound).to be < RestClient::ExceptionWithResponse
  end

  it 'subclasses timeout from RestClient::RequestTimeout, RequestFailed, EWR' do
    expect(RestClient::Exceptions::OpenTimeout).to be < RestClient::Exceptions::Timeout
    expect(RestClient::Exceptions::ReadTimeout).to be < RestClient::Exceptions::Timeout

    expect(RestClient::Exceptions::Timeout).to be < RestClient::RequestTimeout
    expect(RestClient::Exceptions::Timeout).to be < RestClient::RequestFailed
    expect(RestClient::Exceptions::Timeout).to be < RestClient::ExceptionWithResponse
  end

end
