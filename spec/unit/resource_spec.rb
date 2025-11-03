require_relative "_lib"

describe RestClient::Resource do
  before do
    @resource = RestClient::Resource.new("http://some/resource", user: "jane", password: "mypass", headers: { "X-Something" => "1" })
  end

  context "Resource delegation" do
    it "GET" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :get
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:headers]).to eq({ "X-Something" => "1" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.get
    end

    it "HEAD" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :head
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:headers]).to eq({ "X-Something" => "1" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.head
    end

    it "POST" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :post
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:payload]).to eq "abc"
        expect(args[:headers]).to eq({ :content_type => "image/jpg", "X-Something" => "1" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.post "abc", content_type: "image/jpg"
    end

    it "PUT" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :put
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:payload]).to eq "abc"
        expect(args[:headers]).to eq({ :content_type => "image/jpg", "X-Something" => "1" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.put "abc", content_type: "image/jpg"
    end

    it "PATCH" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :patch
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:payload]).to eq "abc"
        expect(args[:headers]).to eq({ :content_type => "image/jpg", "X-Something" => "1" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.patch "abc", content_type: "image/jpg"
    end

    it "DELETE" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :delete
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:headers]).to eq({ "X-Something" => "1" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.delete
    end

    it "overrides resource headers" do
      expect(RestClient::Request).to receive(:execute) do |args|
        expect(args[:method]).to eq :get
        expect(args[:url]).to eq "http://some/resource"
        expect(args[:headers]).to eq({ "X-Something" => "2" })
        expect(args[:user]).to eq "jane"
        expect(args[:password]).to eq "mypass"
        expect(args[:log]).to be_nil
      end
      @resource.get "X-Something" => "2"
    end
  end

  it "can instantiate with no user/password" do
    @resource = RestClient::Resource.new("http://some/resource")
  end

  it "is backwards compatible with previous constructor" do
    @resource = RestClient::Resource.new("http://some/resource", "user", "pass")
    expect(@resource.user).to eq "user"
    expect(@resource.password).to eq "pass"
  end

  it "concatenates urls, inserting a slash when it needs one" do
    expect(@resource.concat_urls("http://example.com", "resource")).to eq "http://example.com/resource"
  end

  it "concatenates urls, using no slash if the first url ends with a slash" do
    expect(@resource.concat_urls("http://example.com/", "resource")).to eq "http://example.com/resource"
  end

  it "concatenates urls, using no slash if the second url starts with a slash" do
    expect(@resource.concat_urls("http://example.com", "/resource")).to eq "http://example.com/resource"
  end

  it "concatenates even non-string urls, :posts + 1 => 'posts/1'" do
    expect(@resource.concat_urls(:posts, 1)).to eq "posts/1"
  end

  it "offers subresources via []" do
    parent = RestClient::Resource.new("http://example.com")
    expect(parent["posts"].url).to eq "http://example.com/posts"
  end

  it "transports options to subresources" do
    parent = RestClient::Resource.new("http://example.com", user: "user", password: "password")
    expect(parent["posts"].user).to eq "user"
    expect(parent["posts"].password).to eq "password"
  end

  it "passes a given block to subresources" do
    block = proc { |r| r }
    parent = RestClient::Resource.new("http://example.com", &block)
    expect(parent["posts"].block).to eq block
  end

  it "the block should be overrideable" do
    block1 = proc { |r| r }
    block2 = proc { |r| }
    parent = RestClient::Resource.new("http://example.com", &block1)
    # parent['posts', &block2].block.should eq block2 # ruby 1.9 syntax
    expect(parent.send(:[], "posts", &block2).block).to eq block2
    expect(parent.send(:[], "posts", &block2).block).not_to eq block1
  end

  # Test fails on jruby 9.1.[0-5].* due to
  # https://github.com/jruby/jruby/issues/4217
  it "the block should be overrideable in ruby 1.9 syntax",
    unless: (RUBY_ENGINE == "jruby" && JRUBY_VERSION =~ /\A9\.1\.[0-5]\./) \
  do
    block1 = proc { |r| r }
    block2 = ->(r) {}

    parent = RestClient::Resource.new("http://example.com", &block1)
    expect(parent["posts", &block2].block).to eq block2
    expect(parent["posts", &block2].block).not_to eq block1
  end

  it "prints its url with to_s" do
    expect(RestClient::Resource.new("x").to_s).to eq "x"
  end

  describe "block" do
    it "can use block when creating the resource" do
      stub_request(:get, "www.example.com").to_return(body: "", status: 404)
      resource = RestClient::Resource.new("www.example.com") { |response, request| "foo" }
      expect(resource.get).to eq "foo"
    end

    it "can use block when executing the resource" do
      stub_request(:get, "www.example.com").to_return(body: "", status: 404)
      resource = RestClient::Resource.new("www.example.com")
      expect(resource.get { |response, request| "foo" }).to eq "foo"
    end

    it "execution block override resource block" do
      stub_request(:get, "www.example.com").to_return(body: "", status: 404)
      resource = RestClient::Resource.new("www.example.com") { |response, request| "foo" }
      expect(resource.get { |response, request| "bar" }).to eq "bar"
    end

  end
end
