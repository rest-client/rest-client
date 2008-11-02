require File.dirname(__FILE__) + '/base'

describe RestClient::Resource do
	before do
		@resource = RestClient::Resource.new('http://some/resource', :user => 'jane', :password => 'mypass', :headers => { 'X-Something' => '1'})
	end

	context "Resource delegation" do
		it "GET" do
			RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => { 'X-Something' => '1'}, :user => 'jane', :password => 'mypass')
			@resource.get
		end

		it "POST" do
			RestClient::Request.should_receive(:execute).with(:method => :post, :url => 'http://some/resource', :payload => 'abc', :headers => { :content_type => 'image/jpg', 'X-Something' => '1'}, :user => 'jane', :password => 'mypass')
			@resource.post 'abc', :content_type => 'image/jpg'
		end

		it "PUT" do
			RestClient::Request.should_receive(:execute).with(:method => :put, :url => 'http://some/resource', :payload => 'abc', :headers => { :content_type => 'image/jpg', 'X-Something' => '1'}, :user => 'jane', :password => 'mypass')
			@resource.put 'abc', :content_type => 'image/jpg'
		end

		it "DELETE" do
			RestClient::Request.should_receive(:execute).with(:method => :delete, :url => 'http://some/resource', :headers => { 'X-Something' => '1'}, :user => 'jane', :password => 'mypass')
			@resource.delete
		end

		it "overrides resource headers" do
			RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => { 'X-Something' => '2'}, :user => 'jane', :password => 'mypass')
			@resource.get 'X-Something' => '2'
		end
	end

	it "can instantiate with no user/password" do
		@resource = RestClient::Resource.new('http://some/resource')
	end

	it "is backwards compatible with previous constructor" do
		@resource = RestClient::Resource.new('http://some/resource', 'user', 'pass')
		@resource.user.should == 'user'
		@resource.password.should == 'pass'
	end

	it "concatinates urls, inserting a slash when it needs one" do
		@resource.concat_urls('http://example.com', 'resource').should == 'http://example.com/resource'
	end

	it "concatinates urls, using no slash if the first url ends with a slash" do
		@resource.concat_urls('http://example.com/', 'resource').should == 'http://example.com/resource'
	end

	it "concatinates urls, using no slash if the second url starts with a slash" do
		@resource.concat_urls('http://example.com', '/resource').should == 'http://example.com/resource'
	end

	it "concatinates even non-string urls, :posts + 1 => 'posts/1'" do
		@resource.concat_urls(:posts, 1).should == 'posts/1'
	end

	it "offers subresources via []" do
		parent = RestClient::Resource.new('http://example.com')
		parent['posts'].url.should == 'http://example.com/posts'
	end

	it "transports options to subresources" do
		parent = RestClient::Resource.new('http://example.com', :user => 'user', :password => 'password')
		parent['posts'].user.should == 'user'
		parent['posts'].password.should == 'password'
	end

	it "prints its url with to_s" do
		RestClient::Resource.new('x').to_s.should == 'x'
	end
end
