require File.dirname(__FILE__) + "/base"

describe RestClient::Payload do
  context "A regular Payload" do
    it "should use standard enctype as default content-type" do
      RestClient::Payload::UrlEncoded.new({}).headers['Content-Type'].
              should == 'application/x-www-form-urlencoded'
    end

    it "should form properly encoded params" do
      RestClient::Payload::UrlEncoded.new({:foo => 'bar'}).to_s.
              should == "foo=bar"
      ["foo=bar&baz=qux", "baz=qux&foo=bar"].should include(
      RestClient::Payload::UrlEncoded.new({:foo => 'bar', :baz => 'qux'}).to_s)
    end

    it "should properly handle hashes as parameter" do
      RestClient::Payload::UrlEncoded.new({:foo => {:bar => 'baz' }}).to_s.
              should == "foo[bar]=baz"
      RestClient::Payload::UrlEncoded.new({:foo => {:bar => {:baz => 'qux' }}}).to_s.
              should == "foo[bar][baz]=qux"
    end

    it "should form properly use symbols as parameters" do
      RestClient::Payload::UrlEncoded.new({:foo => :bar}).to_s.
              should == "foo=bar"
      RestClient::Payload::UrlEncoded.new({:foo => {:bar => :baz }}).to_s.
              should == "foo[bar]=baz"
    end

    it "should properyl handle arrays as repeated parameters" do
      RestClient::Payload::UrlEncoded.new({:foo => ['bar']}).to_s.
              should == "foo=bar"
      RestClient::Payload::UrlEncoded.new({:foo => ['bar', 'baz']}).to_s.
              should == "foo=bar&foo=baz"
    end

  end

  context "A multipart Payload" do
    it "should use standard enctype as default content-type" do
      m = RestClient::Payload::Multipart.new({})
      m.stub!(:boundary).and_return(123)
      m.headers['Content-Type'].should == 'multipart/form-data; boundary="123"'
    end

    it "should form properly separated multipart data" do
      m = RestClient::Payload::Multipart.new([[:bar, "baz"], [:foo, "bar"]])
      m.to_s.should == <<-EOS
--#{m.boundary}\r
Content-Disposition: form-data; name="bar"\r
\r
baz\r
--#{m.boundary}\r
Content-Disposition: form-data; name="foo"\r
\r
bar\r
--#{m.boundary}--\r
      EOS
    end

    it "should form properly separated multipart data" do
      f = File.new(File.dirname(__FILE__) + "/master_shake.jpg")
      m = RestClient::Payload::Multipart.new({:foo => f})
      m.to_s.should == <<-EOS
--#{m.boundary}\r
Content-Disposition: form-data; name="foo"; filename="master_shake.jpg"\r
Content-Type: image/jpeg\r
\r
#{IO.read(f.path)}\r
--#{m.boundary}--\r
      EOS
    end

    it "should detect optional (original) content type and filename" do
      f = File.new(File.dirname(__FILE__) + "/master_shake.jpg")
      f.instance_eval "def content_type; 'text/plain'; end"
      f.instance_eval "def original_filename; 'foo.txt'; end"
      m = RestClient::Payload::Multipart.new({:foo => f})
      m.to_s.should == <<-EOS
--#{m.boundary}\r
Content-Disposition: form-data; name="foo"; filename="foo.txt"\r
Content-Type: text/plain\r
\r
#{IO.read(f.path)}\r
--#{m.boundary}--\r
      EOS
    end

    it "should handle hash in hash parameters" do
      m = RestClient::Payload::Multipart.new({:bar => {:baz => "foo"}})
      m.to_s.should == <<-EOS
--#{m.boundary}\r
Content-Disposition: form-data; name="bar[baz]"\r
\r
foo\r
--#{m.boundary}--\r
      EOS

      f = File.new(File.dirname(__FILE__) + "/master_shake.jpg")
      f.instance_eval "def content_type; 'text/plain'; end"
      f.instance_eval "def original_filename; 'foo.txt'; end"
      m = RestClient::Payload::Multipart.new({:foo => {:bar => f}})
      m.to_s.should == <<-EOS
--#{m.boundary}\r
Content-Disposition: form-data; name="foo[bar]"; filename="foo.txt"\r
Content-Type: text/plain\r
\r
#{IO.read(f.path)}\r
--#{m.boundary}--\r
      EOS
    end

  end

  context "Payload generation" do
    it "should recognize standard urlencoded params" do
      RestClient::Payload.generate({"foo" => 'bar'}).should be_kind_of(RestClient::Payload::UrlEncoded)
    end

    it "should recognize multipart params" do
      f = File.new(File.dirname(__FILE__) + "/master_shake.jpg")
      RestClient::Payload.generate({"foo" => f}).should be_kind_of(RestClient::Payload::Multipart)
    end

    it "should be multipart if forced" do
      RestClient::Payload.generate({"foo" => "bar", :multipart => true}).should be_kind_of(RestClient::Payload::Multipart)
    end

    it "should return data if no of the above" do
      RestClient::Payload.generate("data").should be_kind_of(RestClient::Payload::Base)
    end

    it "should recognize nested multipart payloads" do
      f = File.new(File.dirname(__FILE__) + "/master_shake.jpg")
      RestClient::Payload.generate({"foo" => {"file" => f}}).should be_kind_of(RestClient::Payload::Multipart)
    end

  end
end
