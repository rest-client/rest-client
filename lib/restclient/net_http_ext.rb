module Net
  class HTTP    
    
  # Adding the patch method if it doesn't exist (rest-client issue: https://github.com/archiloque/rest-client/issues/79)
  if !defined?(Net::HTTP::Patch)
    # Code taken from this commit: https://github.com/ruby/ruby/commit/ab70e53ac3b5102d4ecbe8f38d4f76afad29d37d#lib/net/http.rb
    class Protocol
      # Sends a PATCH request to the +path+ and gets a response,
      # as an HTTPResponse object.
      def patch(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
        send_entity(path, data, initheader, dest, Patch, &block)
      end
      
      # Executes a request which uses a representation
      # and returns its body.
      def send_entity(path, data, initheader, dest, type, &block)
        res = nil
        request(type.new(path, initheader), data) {|r|
          r.read_body dest, &block
          res = r
        }
        unless @newimpl
          res.value
          return res, res.body
        end
        res
      end
    end
    
    class Patch < HTTPRequest
      METHOD = 'PATCH'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end
  end

    #
    # Replace the request method in Net::HTTP to sniff the body type
    # and set the stream if appropriate
    #
    # Taken from:	
    # http://www.missiondata.com/blog/ruby/29/streaming-data-to-s3-with-ruby/

    alias __request__ request

    def request(req, body=nil, &block)
      if body != nil && body.respond_to?(:read)
        req.body_stream = body
        return __request__(req, nil, &block)
      else
        return __request__(req, body, &block)
      end
    end
  end
end
