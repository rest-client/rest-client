require File.join( File.dirname(File.expand_path(__FILE__)), '../spec_helper')

describe RestClient::Request do
  describe "ssl verification" do
    before(:each) { WebMock.allow_net_connect! }
    after(:each) { WebMock.disable_net_connect! }

    it "is successful with the correct ca_file" do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.com',
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => File.expand_path('spec/fixtures/certs/mozilla.org.crt')
      )
      expect { request.execute }.to_not raise_error
    end

    it "is unsuccessful with an incorrect ca_file" do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.org',
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "equifax.crt")
      )
      expect { request.execute }.to raise_error(RestClient::SSLCertificateNotVerified)
    end
  end
end
