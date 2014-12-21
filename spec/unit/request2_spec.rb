require 'spec_helper'

describe RestClient::Request do

  it "manage params for get requests" do
    stub_request(:get, 'http://some/resource?a=b&c=d').with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip, deflate', 'Foo'=>'bar'}).to_return(:body => 'foo', :status => 200)
    expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :headers => {:foo => :bar, :params => {:a => :b, 'c' => 'd'}}).body).to eq 'foo'

    stub_request(:get, 'http://some/resource').with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip, deflate', 'Foo'=>'bar', 'params' => 'a'}).to_return(:body => 'foo', :status => 200)
    expect(RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :headers => {:foo => :bar, :params => :a}).body).to eq 'foo'
  end

  it "can use a block to process response" do
    response_value = nil
    block = proc do |http_response|
      response_value = http_response.body
    end
    stub_request(:get, 'http://some/resource?a=b&c=d').with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip, deflate', 'Foo'=>'bar'}).to_return(:body => 'foo', :status => 200)
    RestClient::Request.execute(:url => 'http://some/resource', :method => :get, :headers => {:foo => :bar, :params => {:a => :b, 'c' => 'd'}}, :block_response => block)
    expect(response_value).to eq "foo"
  end

  it 'closes payload if not nil' do
    test_file = File.new(File.join( File.dirname(File.expand_path(__FILE__)), 'master_shake.jpg'))

    stub_request(:post, 'http://some/resource').with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip, deflate'}).to_return(:body => 'foo', :status => 200)
    RestClient::Request.execute(:url => 'http://some/resource', :method => :post, :payload => {:file => test_file})

    expect(test_file.closed?).to be_truthy
  end

end
