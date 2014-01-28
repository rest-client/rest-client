module RestClient
  class Connection

    include RestClient::Util
    PARAMS = %w{
url host port timeout open_timeout verify_ssl ssl_client_cert
ssl_client_key ssl_ca_file ssl_ca_path ssl_version 
    }

    PARAMS.each do |attr|
      attr_reader attr
    end

    attr_reader :err_msg
    attr_writer :host, :port

    def parse_args args
      PARAMS.each do |attr|
        instance_variable_set("@#{attr}", args[attr.to_sym]) if args[attr.to_sym]
      end

      @uri = parse_url(@url) if @url
      @port ||= 80
      @verify_ssl ||= false
      @ssl_version ||= 'SSLv3'
    end

    def initialize args
      parse_args args
    end

    def make_connection
      if @uri
        net = RestClient::Util.net_http_class.new(@uri.host, @uri.port)
      else
        net = RestClient::Util.net_http_class.new(host, port)
      end
      net.use_ssl = port == 443
      net.ssl_version = @ssl_version
      @err_msg = nil
      if (@verify_ssl == false) || (@verify_ssl == OpenSSL::SSL::VERIFY_NONE)
        net.verify_mode = OpenSSL::SSL::VERIFY_NONE
      elsif @verify_ssl.is_a? Integer
        net.verify_mode = @verify_ssl
        net.verify_callback = lambda do |preverify_ok, ssl_context|
          if (!preverify_ok) || ssl_context.error != 0
            @err_msg = 
              "SSL Verification failed -- Preverify: #{preverify_ok}, \
              Error: #{ssl_context.error_string} (#{ssl_context.error})"
            return false
          end
          true
        end
      end
      net.cert = @ssl_client_cert if @ssl_client_cert
      net.key = @ssl_client_key if @ssl_client_key
      net.ca_file = @ssl_ca_file if @ssl_ca_file
      net.ca_path = @ssl_ca_path if @ssl_ca_path
      net.read_timeout = @timeout if @timeout
      net.open_timeout = @open_timeout if @open_timeout

      # disable the timeout if the timeout value is -1
      net.read_timeout = nil if @timeout == -1
      net.open_timeout = nil if @open_timeout == -1
      net
    end

    def net
      @net ||= make_connection
    end
  end
end
