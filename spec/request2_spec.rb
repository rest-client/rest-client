require File.join( File.dirname(File.expand_path(__FILE__)), 'base')

require 'webmock/rspec'
include WebMock

describe RestClient::Request do

  it "manage params for get requests" do
    stub_request(:get, 'http://some/resource?a=b&c=d').with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'Foo'=>'bar'}).to_return(:body => 'foo', :status => 200)
    RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :headers => {:foo => :bar, :params => {:a => :b, 'c' => 'd'}}).body.should == 'foo'

    stub_request(:get, 'http://some/resource').with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'Foo'=>'bar', 'params' => 'a'}).to_return(:body => 'foo', :status => 200)
    RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :headers => {:foo => :bar, :params => :a}).body.should == 'foo'
  end

  it "can use a block to process response" do
    response_value = nil
    block = Proc.new do |http_response|
      response_value = http_response.body
    end
    stub_request(:get, 'http://some/resource?a=b&c=d').with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate', 'Foo'=>'bar'}).to_return(:body => 'foo', :status => 200)
    RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :headers => {:foo => :bar, :params => {:a => :b, 'c' => 'd'}}, :block_response => block)
    response_value.should == "foo"
  end

  it 'closes payload if not nil' do
    test_file = File.new(File.join( File.dirname(File.expand_path(__FILE__)), 'master_shake.jpg'))
    initial_count = tmp_count

    stub_request(:post, 'http://some/resource').with(:headers => {'Accept'=>'*/*; q=0.5, application/xml', 'Accept-Encoding'=>'gzip, deflate'}).to_return(:body => 'foo', :status => 200)
    RestClient::Request.execute(:url => 'http://some/resource', :method => :post, :payload => {:file => test_file})

    tmp_count.should == initial_count
  end

end

def tmp_count
  Dir.glob(Dir::tmpdir + "/*").size
end