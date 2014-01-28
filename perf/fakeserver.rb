require 'webrick'
require 'rack'
require 'thread'

s = WEBrick::HTTPServer.new Port: 3355

class Res
  def call(env)
    [
      200, 
      {'Content-Type' => 'application/json'}, 
      ["Hello World" * 10]
    ]
  end
end

s.mount "/", Rack::Handler::WEBrick, Res.new

Signal.trap("TERM") {s.shutdown}
Signal.trap("SIGINT") {s.shutdown}

s.start

