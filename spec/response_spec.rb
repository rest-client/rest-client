require File.dirname(__FILE__) + '/base'

describe RestClient::Response do
  before do
    @net_http_res = mock('net http response', :to_hash => {"Status" => ["200 OK"]})
    @response = RestClient::Response.new('abc', @net_http_res)
  end

  it "behaves like string" do
    @response.should == 'abc'
  end

  it "accepts nil strings and sets it to empty for the case of HEAD" do
    RestClient::Response.new(nil, @net_http_res).should == ""
  end

  it "test headers and raw headers" do
    @response.raw_headers["Status"][0].should == "200 OK"
    @response.headers[:status].should == "200 OK"
  end
  
  describe "cookie processing" do
    it "should correctly deal with one Set-Cookie header with one cookie inside" do
      net_http_res = mock('net http response', :to_hash => {"etag" => ["\"e1ac1a2df945942ef4cac8116366baad\""], "set-cookie" => ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT"]})
      response = RestClient::Response.new('abc', net_http_res)
      response.headers[:set_cookie].should == ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT"]
      response.cookies.should == {  "main_page" => "main_page_no_rewrite" }
    end

    it "should correctly deal with multiple cookies [multiple Set-Cookie headers]" do
      net_http_res = mock('net http response', :to_hash => {"etag" => ["\"e1ac1a2df945942ef4cac8116366baad\""], "set-cookie" => ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT", "remember_me=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT", "user=somebody; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT"]})
      response = RestClient::Response.new('abc', net_http_res)
      response.headers[:set_cookie].should == ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT", "remember_me=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT", "user=somebody; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT"]
      response.cookies.should == {
        "main_page" => "main_page_no_rewrite",
        "remember_me" => "",
        "user" => "somebody"
      }
    end

    it "should correctly deal with multiple cookies [one Set-Cookie header with multiple cookies]" do
      net_http_res = mock('net http response', :to_hash => {"etag" => ["\"e1ac1a2df945942ef4cac8116366baad\""], "set-cookie" => ["main_page=main_page_no_rewrite; path=/; expires=Tue, 20-Jan-2015 15:03:14 GMT, remember_me=; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT, user=somebody; path=/; expires=Thu, 01-Jan-1970 00:00:00 GMT"]})
      response = RestClient::Response.new('abc', net_http_res)
      response.cookies.should == {
        "main_page" => "main_page_no_rewrite",
        "remember_me" => "",
        "user" => "somebody"
      }
    end
  end

end
