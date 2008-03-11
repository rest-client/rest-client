require File.dirname(__FILE__) + '/base'

describe RestClient::Resource do
	before do
		@resource = RestClient::Resource.new('http://some/resource', 'jane', 'mypass')
	end

	it "GET" do
		RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => {}, :user => 'jane', :password => 'mypass')
		@resource.get
	end

	it "POST" do
		RestClient::Request.should_receive(:execute).with(:method => :post, :url => 'http://some/resource', :payload => 'abc', :headers => { :content_type => 'image/jpg' }, :user => 'jane', :password => 'mypass')
		@resource.post 'abc', :content_type => 'image/jpg'
	end

	it "PUT" do
		RestClient::Request.should_receive(:execute).with(:method => :put, :url => 'http://some/resource', :payload => 'abc', :headers => { :content_type => 'image/jpg' }, :user => 'jane', :password => 'mypass')
		@resource.put 'abc', :content_type => 'image/jpg'
	end

	it "DELETE" do
		RestClient::Request.should_receive(:execute).with(:method => :delete, :url => 'http://some/resource', :headers => {}, :user => 'jane', :password => 'mypass')
		@resource.delete
	end
end
