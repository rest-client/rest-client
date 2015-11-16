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

  describe '.find_encoding' do
    it 'finds various normal encoding names' do
      {
        'utf-8' => Encoding::UTF_8,
        'big5' => Encoding::Big5,
        'euc-kr' => Encoding::EUC_KR,
        'WINDOWS-1252' => Encoding::Windows_1252,
        'windows-31j' => Encoding::Windows_31J,
      }.each_pair do |name, enc|
        RestClient::Utils.find_encoding(name).should eq enc
      end
    end

    it 'returns nil on failures' do
      %w{nonexistent utf-99}.each do |name|
        RestClient::Utils.find_encoding(name).should be_nil
      end
    end

    it 'uses URI.get_encoding if available', if: RUBY_VERSION >= '2.1' do
      {
        'utf8' => Encoding::UTF_8,
        'utf-16' => Encoding::UTF_16LE,
        'latin1' => Encoding::Windows_1252,
        'iso-8859-1' => Encoding::Windows_1252,
        'shift_jis' => Encoding::Windows_31J,
        'euc-jp' => Encoding::CP51932,
      }.each_pair do |name, enc|
        RestClient::Utils.find_encoding(name).should eq enc
      end
    end

    it 'uses Encoding.find if URI.get_encoding unavailable', if: RUBY_VERSION < '2.1' do
      {
        'utf8' => nil,
        'utf-16' => Encoding::UTF_16,
        'latin1' => nil,
        'iso-8859-1' => Encoding::ISO_8859_1,
        'shift_jis' => Encoding::Shift_JIS,
        'euc-jp' => Encoding::EUC_JP,
      }.each_pair do |name, enc|
        RestClient::Utils.find_encoding(name).should eq enc
      end
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
end
