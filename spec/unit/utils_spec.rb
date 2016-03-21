require_relative '_lib'

describe RestClient::Utils do
  describe '.get_encoding_from_headers' do
    it 'assumes no encoding by default for text' do
      headers = {:content_type => 'text/plain'}
      RestClient::Utils.get_encoding_from_headers(headers).
        should eq nil
    end

    it 'returns nil on failures' do
      RestClient::Utils.get_encoding_from_headers(
        {:content_type => 'blah'}).should eq nil
      RestClient::Utils.get_encoding_from_headers(
        {}).should eq nil
      RestClient::Utils.get_encoding_from_headers(
        {:content_type => 'foo; bar=baz'}).should eq nil
    end

    it 'handles various charsets' do
      RestClient::Utils.get_encoding_from_headers(
        {:content_type => 'text/plain; charset=UTF-8'}).should eq 'UTF-8'
      RestClient::Utils.get_encoding_from_headers(
        {:content_type => 'application/json; charset=ISO-8859-1'}).
        should eq 'ISO-8859-1'
      RestClient::Utils.get_encoding_from_headers(
        {:content_type => 'text/html; charset=windows-1251'}).
        should eq 'windows-1251'

      RestClient::Utils.get_encoding_from_headers(
        {:content_type => 'text/html; charset="UTF-16"'}).
        should eq 'UTF-16'
    end
  end

  describe '.cgi_parse_header' do
    it 'parses headers' do
      RestClient::Utils.cgi_parse_header('text/plain').
        should eq ['text/plain', {}]

      RestClient::Utils.cgi_parse_header('text/vnd.just.made.this.up ; ').
        should eq ['text/vnd.just.made.this.up', {}]

      RestClient::Utils.cgi_parse_header('text/plain;charset=us-ascii').
        should eq ['text/plain', {'charset' => 'us-ascii'}]

      RestClient::Utils.cgi_parse_header('text/plain ; charset="us-ascii"').
        should eq ['text/plain', {'charset' => 'us-ascii'}]

      RestClient::Utils.cgi_parse_header(
        'text/plain ; charset="us-ascii"; another=opt').
        should eq ['text/plain', {'charset' => 'us-ascii', 'another' => 'opt'}]

      RestClient::Utils.cgi_parse_header(
        'attachment; filename="silly.txt"').
        should eq ['attachment', {'filename' => 'silly.txt'}]

      RestClient::Utils.cgi_parse_header(
        'attachment; filename="strange;name"').
        should eq ['attachment', {'filename' => 'strange;name'}]

      RestClient::Utils.cgi_parse_header(
        'attachment; filename="strange;name";size=123;').should eq \
        ['attachment', {'filename' => 'strange;name', 'size' => '123'}]

      RestClient::Utils.cgi_parse_header(
        'form-data; name="files"; filename="fo\\"o;bar"').should eq \
        ['form-data', {'name' => 'files', 'filename' => 'fo"o;bar'}]
    end
  end

  describe '.parse_url' do
    it "parses a url into a URI object" do
      URI.should_receive(:parse).with('http://example.com/resource')
      RestClient::Utils.parse_url('http://example.com/resource')
    end

    it "adds http:// to the front of resources specified in the syntax example.com/resource" do
      URI.should_receive(:parse).with('http://example.com/resource')
      RestClient::Utils.parse_url('example.com/resource')
    end

    it 'adds http:// to resources containing a colon' do
      URI.should_receive(:parse).with('http://example.com:1234')
      RestClient::Utils.parse_url('example.com:1234')
    end

    it 'does not add http:// to the front of https resources' do
      URI.should_receive(:parse).with('https://example.com/resource')
      RestClient::Utils.parse_url('https://example.com/resource')
    end

    it 'does not add http:// to the front of capital HTTP resources' do
      URI.should_receive(:parse).with('HTTP://example.com/resource')
      RestClient::Utils.parse_url('HTTP://example.com/resource')
    end

    it 'does not add http:// to the front of capital HTTPS resources' do
      URI.should_receive(:parse).with('HTTPS://example.com/resource')
      RestClient::Utils.parse_url('HTTPS://example.com/resource')
    end

    it 'raises with invalid URI' do
      lambda {
        RestClient::Utils.parse_url('http://a@b:c')
      }.should raise_error(URI::InvalidURIError)
      lambda {
        RestClient::Utils.parse_url('http://::')
      }.should raise_error(URI::InvalidURIError)
    end
  end
end
