require File.join( File.dirname(File.expand_path(__FILE__)), '../base')

describe RestClient::Request do
  describe "ssl verification" do
    it "is successful with the correct ca_file" do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.org',
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "digicert.crt")
      )
      expect { request.execute }.to_not raise_error
    end

    # I don' think this feature is useful anymore (under 1.9.3 at the very least).
    #
    # Exceptions in verify_callback are ignored; RestClient has to catch OpenSSL::SSL::SSLError
    # and either re-throw it as is, or throw SSLCertificateNotVerified
    # based on the contents of the message field of the original exception
    #.
    # The client has to handle OpenSSL::SSL::SSLError exceptions anyway,
    # why make them handle both OpenSSL *AND* RestClient exceptions???
    #
    # also see https://github.com/ruby/ruby/blob/trunk/ext/openssl/ossl.c#L237
    it "is unsuccessful with an incorrect ca_file" do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.com',
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "verisign.crt")
      )
      expect { request.execute }.to raise_error(RestClient::SSLCertificateNotVerified)
    end

    it "executes the verify_callback" do
      ran_callback = false
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.org',
        :verify_ssl => true,
        :ssl_verify_callback => lambda { |preverify_ok, store_ctx|
          ran_callback = true
          preverify_ok
        },
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "digicert.crt")
      )
      expect {request.execute }.to_not raise_error
      ran_callback.should eq(true)
    end

    it "fails verification when the callback returns false",
       :unless => RestClient::Platform.mac? do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.org',
        :verify_ssl => true,
        :ssl_verify_callback => lambda { |preverify_ok, store_ctx| false },
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "digicert.crt")
      )
      expect { request.execute }.to raise_error(RestClient::SSLCertificateNotVerified)
    end

    it "succeeds verification when the callback returns true",
       :unless => RestClient::Platform.mac? do
      request = RestClient::Request.new(
        :method => :get,
        :url => 'https://www.mozilla.org',
        :verify_ssl => true,
        :ssl_ca_file => File.join(File.dirname(__FILE__), "certs", "verisign.crt"),
        :ssl_verify_callback => lambda { |preverify_ok, store_ctx| true }
      )
      expect { request.execute }.to_not raise_error
    end
  end
end
