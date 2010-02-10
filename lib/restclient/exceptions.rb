module RestClient

  STATUSES = {100 => 'Continue',
              101 => 'Switching Protocols',
              200 => 'OK',
              201 => 'Created',
              202 => 'Accepted',
              203 => 'Non-Authoritative Information',
              204 => 'No Content',
              205 => 'Reset Content',
              206 => 'Partial Content',
              300 => 'Multiple Choices',
              301 => 'Moved Permanently',
              302 => 'Found',
              303 => 'See Other',
              304 => 'Not Modified',
              305 => 'Use Proxy',
              400 => 'Bad Request',
              401 => 'Unauthorized',
              403 => 'Forbidden',
              404 => 'Resource Not Found',
              405 => 'Method Not Allowed',
              406 => 'Not Acceptable',
              407 => 'Proxy Authentication Required',
              408 => 'Request Timeout',
              409 => 'Conflict',
              410 => 'Gone',
              411 => 'Length Required',
              412 => 'Precondition Failed',
              413 => 'Request Entity Too Large',
              414 => 'Request-URI Too Long',
              415 => 'Unsupported Media Type',
              416 => 'Requested Range Not Satisfiable',
              417 => 'Expectation Failed',
              500 => 'Internal Server Error',
              501 => 'Not Implemented',
              502 => 'Bad Gateway',
              503 => 'Service Unavailable',
              504 => 'Gateway Timeout',
              505 => 'HTTP Version Not Supported'}

  # Compatibility : make the Response act like a Net::HTTPResponse when needed
  module ResponseForException
    def method_missing symbol, *args
      if net_http_res.respond_to? symbol
        warn "[warning] The response contained in an RestClient::Exception is now a RestClient::Response instead of a Net::HTTPResponse, please update your code"
        net_http_res.send symbol, *args
      else
        super
      end
    end
  end

  # This is the base RestClient exception class. Rescue it if you want to
  # catch any exception that your request might raise
  # You can get the status code by e.http_code, or see anything about the
  # response via e.response.
  # For example, the entire result body (which is
  # probably an HTML error page) is e.response.
  class Exception < RuntimeError
    attr_accessor :message, :response

    def initialize response = nil
      @response = response

      # compatibility: this make the exception behave like a Net::HTTPResponse
      response.extend ResponseForException
    end

    def http_code
      # return integer for compatibility
      @response.code.to_i if @response
    end

    def http_body
      @response.body
    end

    def inspect
      "#{self.class} : #{http_code} #{message}"
    end

  end

  # Compatibility
  class ExceptionWithResponse < Exception
  end

  # The request failed with an error code not managed by the code
  class RequestFailed < ExceptionWithResponse

    def message
      "HTTP status code #{http_code}"
    end

    def to_s
      message
    end
  end

  # We will a create an exception for each status code, see http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
  module Exceptions
    # Map http status codes to the corresponding exception class
    EXCEPTIONS_MAP = {}
  end

  STATUSES.each_pair do |code, message|

    # Compatibility
    superclass = ([304, 401, 404].include? code) ? ExceptionWithResponse : RequestFailed
    klass = Class.new(superclass) do
      send(:define_method, :message) {message}
    end
    klass_constant = const_set message.gsub(/ /, '').gsub(/-/, ''), klass
    Exceptions::EXCEPTIONS_MAP[code] = klass_constant
  end

  # A redirect was encountered; caught by execute to retry with the new url.
  class Redirect < Exception

    message = 'Redirect'

    attr_accessor :url

    def initialize(url)
      @url = url
    end
  end

  # The server broke the connection prior to the request completing.  Usually
  # this means it crashed, or sometimes that your network connection was
  # severed before it could complete.
  class ServerBrokeConnection < Exception
    message = 'Server broke connection'
  end



end

# backwards compatibility
class RestClient::Request
  Redirect = RestClient::Redirect
  Unauthorized = RestClient::Unauthorized
  RequestFailed = RestClient::RequestFailed
end
