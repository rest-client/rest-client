require 'uri'

module Helpers
  def res_double(opts={})
    double('Net::HTTPResponse', {to_hash: {}, body: 'response body'}.merge(opts))
  end

  def response_from_res_double(net_http_res_double, request=nil, duration: 1)
    request ||= request_double()
    start_time = Time.now - duration

    response = RestClient::Response.create(net_http_res_double.body, net_http_res_double, request, start_time)

    # mock duration to ensure it gets the value we expect
    allow(response).to receive(:duration).and_return(duration)

    response
  end

  def fake_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end

  def request_double(url: 'http://example.com', method: 'get')
    double('request', url: url, uri: URI.parse(url), method: method,
           user: nil, password: nil, cookie_jar: HTTP::CookieJar.new,
           redirection_history: nil, args: {url: url, method: method})
  end
end
