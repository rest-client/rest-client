require 'resolv'

module RestClient

  # Mandatory parameters:
  # * :url
  # Optional parameters (have a look at ssl and/or uri for some explanations):
  # * :verify_ssl enable ssl verification, possible values are constants from OpenSSL::SSL
  # * :timeout and :open_timeout passing in -1 will disable the timeout by setting the corresponding net timeout values to nil
  # * :ssl_client_cert, :ssl_client_key, :ssl_ca_file, :ssl_ca_path
  # * :ssl_version specifies the SSL version for the underlying Net::HTTP connection (defaults to 'SSLv3')
  # * :host and :port specifies target host address and port 
  
  class Hydra

    attr_reader :connection
    # Usage:
    # RestClient::Hydra.keepalive(host: "example.com") do |conn|
    #   r = RestClient::Request.new(
    #     url: 'http://example.com/help', method: :get, connection: conn)
    #   resp = r.execute
    #
    #   puts resp.code
    # end

    def self.keepalive(args, &block)
      new(args).keepalive(&block)
    end

    def initialize args
      @connection = Connection.new(args)
    end

    def keepalive
      connection.net.start do
        if block_given?
          yield connection
        end
      end
    rescue OpenSSL::SSL::SSLError => e
      if connection.err_msg
        raise SSLCertificateNotVerified.new(connection.err_msg)
      else
        raise e
      end
    rescue EOFError
      raise RestClient::ServerBrokeConnection
    rescue Timeout::Error
      raise RestClient::RequestTimeout
    rescue *RestClient::NETWORKError => e
      sleep 3
      retry
    end
  end
end
