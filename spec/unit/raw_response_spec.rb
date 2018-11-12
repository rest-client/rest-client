require_relative '_lib'

describe RestClient2::RawResponse do
  before do
    @tf = double("Tempfile", :read => "the answer is 42", :open => true, :rewind => true)
    @net_http_res = double('net http response')
    @request = double('restclient2 request', :redirection_history => nil)
    @response = RestClient2::RawResponse.new(@tf, @net_http_res, @request)
  end

  it "behaves like string" do
    expect(@response.to_s).to eq 'the answer is 42'
  end

  it "exposes a Tempfile" do
    expect(@response.file).to eq @tf
  end

  it "includes AbstractResponse" do
    expect(RestClient2::RawResponse.ancestors).to include(RestClient2::AbstractResponse)
  end
end
