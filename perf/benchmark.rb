require 'benchmark'
require File.join(File.dirname(__FILE__), '../lib/restclient')

Benchmark.bm do |b|
  b.report("create connection for each request") do
    1000.times do
      RestClient::Request.execute(
        url: "http://localhost:3355", method: :get)
    end
  end
end

GC.start

Benchmark.bm do |b|
  b.report("use keepalive for each request") do
    RestClient::Hydra.keepalive(url: 'http://localhost:3355') do |conn|
      1000.times do
        RestClient::Request.execute(
          url: "http://localhost:3355", method: :get, connection: conn)
      end
    end
  end
end
