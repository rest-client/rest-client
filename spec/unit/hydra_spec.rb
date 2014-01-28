require 'spec_helper'

describe RestClient::Hydra do
  before do
    @hydra = RestClient::Hydra.new(host: 'example.com')
    @url_1 = 'http://example.com/me'
    @url_2 = 'http://example.com/info'
  end

  it "keep connection active" do
    @hydra.keepalive do |conn|
      req = RestClient::Request.new(
        method: :get, url: @url_1, connection: conn)
      req.connection.should == conn
      conn.net.should be_started

      req2 = RestClient::Request.new(
        method: :get, url: @url_2, connection: conn)
      req2.connection.should == conn
      conn.net.should be_started

    end
    @hydra.connection.net.should_not be_started
  end
end
