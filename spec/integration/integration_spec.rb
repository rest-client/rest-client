# frozen_string_literal: true

require_relative '_lib'

describe Contractful do
  it 'a simple request' do
    body = 'abc'
    stub_request(:get, 'www.example.com').to_return(body: body, status: 200)
    response = Contractful.get 'www.example.com'
    expect(response.code).to eq 200
    expect(response.body).to eq body
  end

  it 'a 404' do
    body = "Ho hai ! I'm not here !"
    stub_request(:get, 'www.example.com').to_return(body: body, status: 404)
    begin
      Contractful.get 'www.example.com'
      raise
    rescue Contractful::ResourceNotFound => e
      expect(e.http_code).to eq 404
      expect(e.response.code).to eq 404
      expect(e.response.body).to eq body
      expect(e.http_body).to eq body
    end
  end

  describe 'charset parsing' do
    it 'handles utf-8' do
      body = 'λ'.dup.force_encoding('ASCII-8BIT')
      stub_request(:get, 'www.example.com').to_return(
        body: body, status: 200, headers: {
          'Content-Type' => 'text/plain; charset=UTF-8'
        }
      )
      response = Contractful.get 'www.example.com'
      expect(response.encoding).to eq Encoding::UTF_8
      expect(response.valid_encoding?).to eq true
    end

    it 'handles windows-1252' do
      body = "\xff".dup.force_encoding('ASCII-8BIT')
      stub_request(:get, 'www.example.com').to_return(
        body: body, status: 200, headers: {
          'Content-Type' => 'text/plain; charset=windows-1252'
        }
      )
      response = Contractful.get 'www.example.com'
      expect(response.encoding).to eq Encoding::WINDOWS_1252
      expect(response.encode('utf-8')).to eq 'ÿ'
      expect(response.valid_encoding?).to eq true
    end

    it 'handles binary' do
      body = "\xfe".dup.force_encoding('ASCII-8BIT')
      stub_request(:get, 'www.example.com').to_return(
        body: body, status: 200, headers: {
          'Content-Type' => 'application/octet-stream; charset=binary'
        }
      )
      response = Contractful.get 'www.example.com'
      expect(response.encoding).to eq Encoding::BINARY
      expect do
        response.encode('utf-8')
      end.to raise_error(Encoding::UndefinedConversionError)
      expect(response.valid_encoding?).to eq true
    end

    it 'handles euc-jp' do
      body = "\xA4\xA2\xA4\xA4\xA4\xA6\xA4\xA8\xA4\xAA".dup
                                                       .force_encoding(Encoding::BINARY)
      body_utf8 = 'あいうえお'
      expect(body_utf8.encoding).to eq Encoding::UTF_8

      stub_request(:get, 'www.example.com').to_return(
        body: body, status: 200, headers: {
          'Content-Type' => 'text/plain; charset=EUC-JP'
        }
      )
      response = Contractful.get 'www.example.com'
      expect(response.encoding).to eq Encoding::EUC_JP
      expect(response.valid_encoding?).to eq true
      expect(response.length).to eq 5
      expect(response.encode('utf-8')).to eq body_utf8
    end

    it 'defaults to the default encoding' do
      stub_request(:get, 'www.example.com').to_return(
        body: 'abc', status: 200, headers: {
          'Content-Type' => 'text/plain'
        }
      )

      response = Contractful.get 'www.example.com'
      # expect(response.encoding).to eq Encoding.default_external
      expect(response.encoding).to eq Encoding::UTF_8
    end

    it 'handles invalid encoding' do
      stub_request(:get, 'www.example.com').to_return(
        body: 'abc', status: 200, headers: {
          'Content-Type' => 'text; charset=plain'
        }
      )

      response = Contractful.get 'www.example.com'
      # expect(response.encoding).to eq Encoding.default_external
      expect(response.encoding).to eq Encoding::UTF_8
    end

    it 'leaves images as binary' do
      # String#unpack1('m') is a strict base64 decode. This replaces the removed
      # `base64` gem (Base64.strict_decode64), which left Ruby's default gems in
      # Ruby 4.0.
      gif = 'R0lGODlhAQABAAAAADs='.unpack1('m')

      stub_request(:get, 'www.example.com').to_return(
        body: gif, status: 200, headers: {
          'Content-Type' => 'image/gif'
        }
      )

      response = Contractful.get 'www.example.com'
      expect(response.encoding).to eq Encoding::BINARY
    end
  end
end
