# frozen_string_literal: true

require_relative '_lib'

describe Contractful::Response, :include_helpers do
  before do
    @net_http_res = res_double(to_hash: { 'Status' => ['200 OK'] }, code: '200', body: 'abc')
    @example_url = 'http://example.com'
    @request = request_double(url: @example_url, method: 'get')
    @response = response_from_res_double(@net_http_res, @request, duration: 1)
  end

  it 'behaves like string' do
    expect(@response.to_s).to eq 'abc'
    expect(@response.to_str).to eq 'abc'

    expect(@response).to receive(:warn)
    expect(@response.to_i).to eq 0
  end

  it 'accepts nil strings and sets it to empty for the case of HEAD' do
    # TODO
    expect(Contractful::Response.create(nil, @net_http_res, @request).to_s).to eq ''
  end

  describe 'json parsing' do
    def json_response(body)
      res = res_double(to_hash: { 'Content-Type' => ['application/json'] },
                       code: '200', body: body)
      response_from_res_double(res, @request, duration: 1)
    end

    it 'parses a JSON object body' do
      expect(json_response('{"a": 1, "b": "two"}').json).to eq(
        { 'a' => 1, 'b' => 'two' }
      )
    end

    it 'parses a JSON array body' do
      expect(json_response('[1, 2, 3]').json).to eq([1, 2, 3])
    end

    it 'forwards keyword arguments to JSON.parse' do
      expect(json_response('{"a": 1}').json(symbolize_names: true)).to eq(
        { a: 1 }
      )
    end

    it 'parses scalars and null' do
      expect(json_response('42').json).to eq 42
      expect(json_response('null').json).to be_nil
    end

    it 'raises JSON::ParserError for invalid JSON' do
      expect { json_response('not json').json }.to raise_error(JSON::ParserError)
    end
  end

  describe 'header processing' do
    it 'test headers and raw headers' do
      expect(@response.raw_headers['Status'][0]).to eq '200 OK'
      expect(@response.headers[:status]).to eq '200 OK'
    end

    it 'handles multiple headers by joining with comma' do
      net_http_res = res_double(to_hash: { 'My-Header' => %w[foo bar] }, code: '200', body: nil)
      example_url = 'http://example.com'
      request = request_double(url: example_url, method: 'get')
      response = response_from_res_double(net_http_res, request)

      expect(response.raw_headers['My-Header']).to eq %w[foo bar]
      expect(response.headers[:my_header]).to eq 'foo, bar'
    end
  end

  describe 'cookie processing' do
    it 'correctlies deal with one Set-Cookie header with one cookie inside' do
      header_val = 'main_page=main_page_no_rewrite; path=/; expires=Sat, 10-Jan-2037 15:03:14 GMT'

      net_http_res = double('net http response', to_hash: { 'etag' => ['"e1ac1a2df945942ef4cac8116366baad"'], 'set-cookie' => [header_val] })
      response = Contractful::Response.create('abc', net_http_res, @request)
      expect(response.headers[:set_cookie]).to eq [header_val]
      expect(response.cookies).to eq({ 'main_page' => 'main_page_no_rewrite' })
    end

    it 'correctlies deal with multiple cookies [multiple Set-Cookie headers]' do
      net_http_res = double('net http response', to_hash: { 'etag' => ['"e1ac1a2df945942ef4cac8116366baad"'], 'set-cookie' => ['main_page=main_page_no_rewrite; path=/; expires=Sat, 10-Jan-2037 15:03:14 GMT', 'remember_me=; path=/; expires=Sat, 10-Jan-2037 00:00:00 GMT', 'user=somebody; path=/; expires=Sat, 10-Jan-2037 00:00:00 GMT'] })
      response = Contractful::Response.create('abc', net_http_res, @request)
      expect(response.headers[:set_cookie]).to eq ['main_page=main_page_no_rewrite; path=/; expires=Sat, 10-Jan-2037 15:03:14 GMT', 'remember_me=; path=/; expires=Sat, 10-Jan-2037 00:00:00 GMT', 'user=somebody; path=/; expires=Sat, 10-Jan-2037 00:00:00 GMT']
      expect(response.cookies).to eq({
                                       'main_page' => 'main_page_no_rewrite',
                                       'remember_me' => '',
                                       'user' => 'somebody'
                                     })
    end

    it 'correctlies deal with multiple cookies [one Set-Cookie header with multiple cookies]' do
      net_http_res = double('net http response', to_hash: { 'etag' => ['"e1ac1a2df945942ef4cac8116366baad"'], 'set-cookie' => ['main_page=main_page_no_rewrite; path=/; expires=Sat, 10-Jan-2037 15:03:14 GMT, remember_me=; path=/; expires=Sat, 10-Jan-2037 00:00:00 GMT, user=somebody; path=/; expires=Sat, 10-Jan-2037 00:00:00 GMT'] })
      response = Contractful::Response.create('abc', net_http_res, @request)
      expect(response.cookies).to eq({
                                       'main_page' => 'main_page_no_rewrite',
                                       'remember_me' => '',
                                       'user' => 'somebody'
                                     })
    end
  end

  describe 'exceptions processing' do
    it 'returns itself for normal codes' do
      ((200..208).to_a + [226]).each do |code|
        net_http_res = res_double(code: code.to_s)
        resp = Contractful::Response.create('abc', net_http_res, @request)
        expect(resp.return!).to equal(resp)
      end
    end

    it 'throws an exception for other codes' do
      Contractful::Exceptions::EXCEPTIONS_MAP.each_pair do |code, exc|
        next if (200..299).include? code

        net_http_res = res_double(code: code.to_i)
        resp = Contractful::Response.create('abc', net_http_res, @request)
        allow(@request).to receive(:max_redirects).and_return(5)
        expect { resp.return! }.to raise_error(exc)
      end
    end
  end

  describe 'redirection' do
    it 'follows a redirection when the request is a get' do
      stub_request(:get, 'http://some/resource').to_return(body: '', status: 301, headers: { 'Location' => 'http://new/resource' })
      stub_request(:get, 'http://new/resource').to_return(body: 'Foo')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :get).body).to eq 'Foo'
    end

    it 'keeps redirection history' do
      stub_request(:get, 'http://some/resource').to_return(body: '', status: 301, headers: { 'Location' => 'http://new/resource' })
      stub_request(:get, 'http://new/resource').to_return(body: 'Foo')
      r = Contractful::Request.execute(url: 'http://some/resource', method: :get)
      expect(r.body).to eq 'Foo'
      expect(r.history.length).to eq 1
      expect(r.history.fetch(0)).to be_a(Contractful::Response)
      expect(r.history.fetch(0).code).to be 301
    end

    it 'keeps credentials on a same-origin redirection' do
      stub_request(:get, 'http://some/resource')
        .with(basic_auth: %w[foo bar], headers: { 'Accept' => 'application/json' })
        .to_return(body: '', status: 301, headers: { 'Location' => 'http://some/next' })
      stub_request(:get, 'http://some/next')
        .with(basic_auth: %w[foo bar], headers: { 'Accept' => 'application/json' })
        .to_return(body: 'Foo')

      expect(
        Contractful::Request.execute(url: 'http://some/resource', method: :get,
                                     user: 'foo', password: 'bar',
                                     headers: { accept: :json }).body
      ).to eq 'Foo'
    end

    it 'strips basic auth on a cross-origin redirection' do
      stub_request(:get, 'http://some/resource')
        .with(basic_auth: %w[foo bar])
        .to_return(body: '', status: 301, headers: { 'Location' => 'http://other/resource' })

      seen_headers = nil
      stub_request(:get, 'http://other/resource').to_return do |request|
        seen_headers = request.headers
        { body: 'Foo' }
      end

      response = Contractful::Request.execute(url: 'http://some/resource', method: :get,
                                              user: 'foo', password: 'bar')

      expect(response.body).to eq 'Foo'
      expect(seen_headers).not_to have_key('Authorization')
    end

    it 'strips explicit authorization headers on a cross-origin redirection' do
      stub_request(:get, 'http://some/resource')
        .with(headers: { 'Authorization' => 'Bearer top-secret' })
        .to_return(body: '', status: 301, headers: { 'Location' => 'http://other/resource' })

      seen_headers = nil
      stub_request(:get, 'http://other/resource').to_return do |request|
        seen_headers = request.headers
        { body: 'Foo' }
      end

      Contractful::Request.execute(url: 'http://some/resource', method: :get,
                                   headers: { authorization: 'Bearer top-secret' })

      expect(seen_headers).not_to have_key('Authorization')
    end

    it 'refuses to follow an https-to-http downgrade' do
      stub_request(:get, 'https://secure.test/resource')
        .to_return(body: '', status: 301, headers: { 'Location' => 'http://plain.test/resource' })
      stub_request(:get, 'http://plain.test/resource').to_return(body: 'insecure')

      expect do
        Contractful::Request.execute(url: 'https://secure.test/resource', method: :get)
      end.to raise_error(Contractful::MovedPermanently)

      expect(a_request(:get, 'http://plain.test/resource')).not_to have_been_made
    end

    it 'follows a redirection and keep the cookies' do
      stub_request(:get, 'http://some/resource').to_return(body: '', status: 301, headers: { 'Set-Cookie' => 'Foo=Bar', 'Location' => 'http://some/new_resource' })
      stub_request(:get, 'http://some/new_resource').with(headers: { 'Cookie' => 'Foo=Bar' }).to_return(body: 'Qux')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :get).body).to eq 'Qux'
    end

    it 'respects cookie domains on redirect' do
      stub_request(:get, 'http://some.example.com/').to_return(body: '', status: 301,
                                                               headers: { 'Set-Cookie' => 'Foo=Bar', 'Location' => 'http://new.example.com/' })
      stub_request(:get, 'http://new.example.com/').with(
        headers: { 'Cookie' => 'passedthrough=1' }
      ).to_return(body: 'Qux')

      expect(Contractful::Request.execute(url: 'http://some.example.com/', method: :get, cookies: [HTTP::Cookie.new('passedthrough', '1', domain: 'new.example.com', path: '/')]).body).to eq 'Qux'
    end

    it "doesn't follow a 301 when the request is a post" do
      net_http_res = res_double(code: 301)
      response = response_from_res_double(net_http_res, request_double(method: 'post'))

      expect do
        response.return!
      end.to raise_error(Contractful::MovedPermanently)
    end

    it "doesn't follow a 302 when the request is a post" do
      net_http_res = res_double(code: 302)
      response = response_from_res_double(net_http_res, request_double(method: 'post'))

      expect do
        response.return!
      end.to raise_error(Contractful::Found)
    end

    it "doesn't follow a 307 when the request is a post" do
      net_http_res = res_double(code: 307)
      response = response_from_res_double(net_http_res, request_double(method: 'post'))

      expect(response).not_to receive(:follow_redirection)
      expect do
        response.return!
      end.to raise_error(Contractful::TemporaryRedirect)
    end

    it "doesn't follow a redirection when the request is a put" do
      net_http_res = res_double(code: 301)
      response = response_from_res_double(net_http_res, request_double(method: 'put'))
      expect do
        response.return!
      end.to raise_error(Contractful::MovedPermanently)
    end

    it 'follows a redirection when the request is a post and result is a 303' do
      stub_request(:put, 'http://some/resource').to_return(body: '', status: 303, headers: { 'Location' => 'http://new/resource' })
      stub_request(:get, 'http://new/resource').to_return(body: 'Foo')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :put).body).to eq 'Foo'
    end

    it 'follows a redirection when the request is a head' do
      stub_request(:head, 'http://some/resource').to_return(body: '', status: 301, headers: { 'Location' => 'http://new/resource' })
      stub_request(:head, 'http://new/resource').to_return(body: 'Foo')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :head).body).to eq 'Foo'
    end

    it 'handles redirects with relative paths' do
      stub_request(:get, 'http://some/resource').to_return(body: '', status: 301, headers: { 'Location' => 'index' })
      stub_request(:get, 'http://some/index').to_return(body: 'Foo')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :get).body).to eq 'Foo'
    end

    it 'handles redirects with relative path and query string' do
      stub_request(:get, 'http://some/resource').to_return(body: '', status: 301, headers: { 'Location' => 'index?q=1' })
      stub_request(:get, 'http://some/index?q=1').to_return(body: 'Foo')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :get).body).to eq 'Foo'
    end

    it 'follow a redirection when the request is a get and the response is in the 30x range' do
      stub_request(:get, 'http://some/resource').to_return(body: '', status: 302, headers: { 'Location' => 'http://new/resource' })
      stub_request(:get, 'http://new/resource').to_return(body: 'Foo')
      expect(Contractful::Request.execute(url: 'http://some/resource', method: :get).body).to eq 'Foo'
    end

    it 'follows no more than 10 redirections before raising error' do
      stub_request(:get, 'http://some/redirect-1').to_return(body: '', status: 301, headers: { 'Location' => 'http://some/redirect-2' })
      stub_request(:get, 'http://some/redirect-2').to_return(body: '', status: 301, headers: { 'Location' => 'http://some/redirect-2' })
      expect do
        Contractful::Request.execute(url: 'http://some/redirect-1', method: :get)
      end.to raise_error(Contractful::MovedPermanently) { |ex|
        expect(ex.response.history).to all(be_a(Contractful::Response))
        expect(ex.response.history.length).to eq 10
      }
      expect(WebMock).to have_requested(:get, 'http://some/redirect-2').times(10)
    end

    it 'follows no more than max_redirects redirections, if specified' do
      stub_request(:get, 'http://some/redirect-1').to_return(body: '', status: 301, headers: { 'Location' => 'http://some/redirect-2' })
      stub_request(:get, 'http://some/redirect-2').to_return(body: '', status: 301, headers: { 'Location' => 'http://some/redirect-2' })
      expect do
        Contractful::Request.execute(url: 'http://some/redirect-1', method: :get, max_redirects: 5)
      end.to raise_error(Contractful::MovedPermanently) { |ex|
        expect(ex.response.history.length).to eq 5
      }
      expect(WebMock).to have_requested(:get, 'http://some/redirect-2').times(5)
    end

    it 'allows for manual following of redirects' do
      stub_request(:get, 'http://some/redirect-1').to_return(body: '', status: 301, headers: { 'Location' => 'http://some/resource' })
      stub_request(:get, 'http://some/resource').to_return(body: 'Qux', status: 200)

      begin
        Contractful::Request.execute(url: 'http://some/redirect-1', method: :get, max_redirects: 0)
      rescue Contractful::MovedPermanently => e
        resp = e.response.follow_redirection
      else
        raise 'notreached'
      end

      expect(resp.code).to eq 200
      expect(resp.body).to eq 'Qux'
    end
  end

  describe 'logging' do
    it "uses the request's logger" do
      stub_request(:get, 'http://some/resource').to_return(body: 'potato', status: 200)

      logger = double('logger', '<<' => true)
      request = Contractful::Request.new(url: 'http://some/resource', method: :get, log: logger)

      expect(logger).to receive(:<<)

      request.execute
    end
  end
end
