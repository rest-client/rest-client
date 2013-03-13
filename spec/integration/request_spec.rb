require File.join( File.dirname(File.expand_path(__FILE__)), '../base')

describe RestClient::Request do
  describe "ssl verification" do
    it "is successful with the correct ca_file" do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.com',
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "equifax.crt")
      )
      expect { request.execute }.to_not raise_error
    end


    # This no longer works (under 1.9.3 at the very least). Exceptions in verify_callback are ignored.
    # see https://github.com/ruby/ruby/blob/trunk/ext/openssl/ossl.c#L237
    it "is unsuccessful with an incorrect ca_file" do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.com',
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "verisign.crt")
      )
      expect { request.execute }.to raise_error(RestClient::SSLCertificateNotVerified)
    end
  end
end
