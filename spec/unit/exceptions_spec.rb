# frozen_string_literal: true

require_relative '_lib'

describe Contractful::Exception do
  it "returns a 'message' equal to the class name if the message is not set, because 'message' should not be nil" do
    e = Contractful::Exception.new
    expect(e.message).to eq 'Contractful::Exception'
  end

  it "returns the 'message' that was set" do
    e = Contractful::Exception.new
    message = 'An explicitly set message'
    e.message = message
    expect(e.message).to eq message
  end

  it 'sets the exception message to ErrorMessage' do
    expect(Contractful::ResourceNotFound.new.message).to eq 'Not Found'
  end

  it 'contains exceptions in Contractful' do
    expect(Contractful::Unauthorized.new).to be_a_kind_of(Contractful::Exception)
    expect(Contractful::ServerBrokeConnection.new).to be_a_kind_of(Contractful::Exception)
  end
end

describe Contractful::ServerBrokeConnection do
  it "has a default message of 'Server broke connection'" do
    e = Contractful::ServerBrokeConnection.new
    expect(e.message).to eq 'Server broke connection'
  end
end

describe Contractful::RequestFailed do
  before do
    @response = double('HTTP Response', code: '502')
  end

  it 'stores the http response on the exception' do
    response = 'response'
    begin
      raise Contractful::RequestFailed, response
    rescue Contractful::RequestFailed => e
      expect(e.response).to eq response
    end
  end

  it 'http_code convenience method for fetching the code as an integer' do
    expect(Contractful::RequestFailed.new(@response).http_code).to eq 502
  end

  it 'http_body convenience method for fetching the body (decoding when necessary)' do
    expect(Contractful::RequestFailed.new(@response).http_code).to eq 502
    expect(Contractful::RequestFailed.new(@response).message).to eq 'HTTP status code 502'
  end

  it 'shows the status code in the message' do
    expect(Contractful::RequestFailed.new(@response).to_s).to match(/502/)
  end
end

describe Contractful::ResourceNotFound do
  it 'also has the http response attached' do
    response = 'response'
    begin
      raise Contractful::ResourceNotFound, response
    rescue Contractful::ResourceNotFound => e
      expect(e.response).to eq response
    end
  end

  it 'stores the body on the response of the exception' do
    body = 'body'
    stub_request(:get, 'www.example.com').to_return(body: body, status: 404)
    begin
      Contractful.get 'www.example.com'
      raise
    rescue Contractful::ResourceNotFound => e
      expect(e.response.body).to eq body
    end
  end
end

describe 'backwards compatibility' do
  it 'aliases Contractful::NotFound as ResourceNotFound' do
    expect(Contractful::ResourceNotFound).to eq Contractful::NotFound
  end

  it 'aliases old names for HTTP 413, 414, 416' do
    expect(Contractful::RequestEntityTooLarge).to eq Contractful::PayloadTooLarge
    expect(Contractful::RequestURITooLong).to eq Contractful::URITooLong
    expect(Contractful::RequestedRangeNotSatisfiable).to eq Contractful::RangeNotSatisfiable
  end

  it 'subclasses NotFound from RequestFailed, ExceptionWithResponse' do
    expect(Contractful::NotFound).to be < Contractful::RequestFailed
    expect(Contractful::NotFound).to be < Contractful::ExceptionWithResponse
  end

  it 'subclasses timeout from Contractful::RequestTimeout, RequestFailed, EWR' do
    expect(Contractful::Exceptions::OpenTimeout).to be < Contractful::Exceptions::Timeout
    expect(Contractful::Exceptions::ReadTimeout).to be < Contractful::Exceptions::Timeout
    expect(Contractful::Exceptions::WriteTimeout).to be < Contractful::Exceptions::Timeout

    expect(Contractful::Exceptions::Timeout).to be < Contractful::RequestTimeout
    expect(Contractful::Exceptions::Timeout).to be < Contractful::RequestFailed
    expect(Contractful::Exceptions::Timeout).to be < Contractful::ExceptionWithResponse
  end
end
