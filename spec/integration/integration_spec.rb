# -*- coding: utf-8 -*-
require_relative '_lib'
require 'base64'

describe RestClient do

  it "a simple request" do
    body = 'abc'
    stub_request(:get, "www.example.com").to_return(:body => body, :status => 200)
    response = RestClient.get "www.example.com"
    response.code.should eq 200
    response.body.should eq body
  end

  it "a simple request with gzipped content" do
    stub_request(:get, "www.example.com").with(:headers => { 'Accept-Encoding' => 'gzip, deflate' }).to_return(:body => "\037\213\b\b\006'\252H\000\003t\000\313T\317UH\257\312,HM\341\002\000G\242(\r\v\000\000\000", :status => 200,  :headers => { 'Content-Encoding' => 'gzip' } )
    response = RestClient.get "www.example.com"
    response.code.should eq 200
    response.body.should eq "i'm gziped\n"
  end

  it "a 404" do
    body = "Ho hai ! I'm not here !"
    stub_request(:get, "www.example.com").to_return(:body => body, :status => 404)
    begin
      RestClient.get "www.example.com"
      raise
    rescue RestClient::ResourceNotFound => e
      e.http_code.should eq 404
      e.response.code.should eq 404
      e.response.body.should eq body
      e.http_body.should eq body
    end
  end

  describe 'charset parsing' do
    it 'handles utf-8' do
      body = "λ".force_encoding('ASCII-8BIT')
      stub_request(:get, "www.example.com").to_return(
        :body => body, :status => 200, :headers => {
          'Content-Type' => 'text/plain; charset=UTF-8'
      })
      response = RestClient.get "www.example.com"
      response.encoding.should eq Encoding::UTF_8
      response.valid_encoding?.should eq true
    end

    it 'handles windows-1252' do
      body = "\xff".force_encoding('ASCII-8BIT')
      stub_request(:get, "www.example.com").to_return(
        :body => body, :status => 200, :headers => {
          'Content-Type' => 'text/plain; charset=windows-1252'
      })
      response = RestClient.get "www.example.com"
      response.encoding.should eq Encoding::WINDOWS_1252
      response.encode('utf-8').should eq "ÿ"
      response.valid_encoding?.should eq true
    end

    it 'handles binary' do
      body = "\xfe".force_encoding('ASCII-8BIT')
      stub_request(:get, "www.example.com").to_return(
        :body => body, :status => 200, :headers => {
          'Content-Type' => 'application/octet-stream; charset=binary'
      })
      response = RestClient.get "www.example.com"
      response.encoding.should eq Encoding::BINARY
      lambda {
        response.encode('utf-8')
      }.should raise_error(Encoding::UndefinedConversionError)
      response.valid_encoding?.should eq true
    end

    it 'handles euc-jp' do
      body = "\xA4\xA2\xA4\xA4\xA4\xA6\xA4\xA8\xA4\xAA".
        force_encoding(Encoding::BINARY)
      body_utf8 = 'あいうえお'
      body_utf8.encoding.should eq Encoding::UTF_8

      stub_request(:get, 'www.example.com').to_return(
        :body => body, :status => 200, :headers => {
          'Content-Type' => 'text/plain; charset=EUC-JP'
      })
      response = RestClient.get 'www.example.com'
      response.encoding.should eq Encoding::EUC_JP
      response.valid_encoding?.should eq true
      response.length.should eq 5
      response.encode('utf-8').should eq body_utf8
    end

    it 'defaults to Encoding.default_external' do
      stub_request(:get, 'www.example.com').to_return(
        body: 'abc', status: 200, headers: {
          'Content-Type' => 'text/plain'
        })

      response = RestClient.get 'www.example.com'
      response.encoding.should eq Encoding.default_external
    end

    it 'leaves images as binary' do
      gif = Base64.strict_decode64('R0lGODlhAQABAAAAADs=')

      stub_request(:get, 'www.example.com').to_return(
        body: gif, status: 200, headers: {
          'Content-Type' => 'image/gif'
        })

      response = RestClient.get 'www.example.com'
      response.encoding.should eq Encoding::BINARY
    end
  end
end
