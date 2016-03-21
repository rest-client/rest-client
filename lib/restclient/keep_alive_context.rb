module RestClient
   class KeepAliveContext
     attr_reader :host_hash

     def initialize
       @host_hash = {}
     end

     def execute(args, & block)
       unless args[:url]
         raise ArgumentError, "must pass url"
       end
       uri = Utils.parse_url(args[:url])

       identifier = "#{uri.scheme}://#{uri.hostname}:#{uri.port}"
       http_object = host_hash[identifier]

       request = Request.new(args.merge(http_object: http_object, keep_alive: true))
       response = request.execute(& block)
       host_hash[identifier] = request.http_object
       response
     end

     def finish
       host_hash.each do |key, http_object|
         http_object.finish if http_object
       end
     end

     def self.start
       KeepAliveContext context = KeepAliveContext.new
       if block_given?
         begin
           return yield(context)
         ensure
           context.finish
         end
       else
         raise ArgumentError, "must pass block"
       end
     end
   end
end