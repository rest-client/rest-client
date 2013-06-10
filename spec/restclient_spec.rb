require File.join( File.dirname(File.expand_path(__FILE__)), 'base')

describe RestClient do
  describe "API" do
    describe "GET" do
      context "without proxy" do
        it "should delegate to RestClient::Request with an empty proxy" do
          RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => {}, proxy: nil)
          RestClient.get('http://some/resource')
        end
      end

      context "with proxy" do
        it "should delegate to RestClient::Request, passing the proxy straight-through" do
          RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => {}, proxy: "proxy.foo")
          RestClient.get('http://some/resource', {}, "proxy.foo")
        end
      end
    end


    it "POST" do
      RestClient::Request.should_receive(:execute).with(hash_including(:method => :post, :url => 'http://some/resource', :payload => 'payload', :headers => {}))
      RestClient.post('http://some/resource', 'payload')
    end

    it "PUT" do
      RestClient::Request.should_receive(:execute).with(hash_including(:method => :put, :url => 'http://some/resource', :payload => 'payload', :headers => {}))
      RestClient.put('http://some/resource', 'payload')
    end

    it "PATCH" do
      RestClient::Request.should_receive(:execute).with(hash_including(:method => :patch, :url => 'http://some/resource', :payload => 'payload', :headers => {}))
      RestClient.patch('http://some/resource', 'payload')
    end

    it "DELETE" do
      RestClient::Request.should_receive(:execute).with(hash_including(:method => :delete, :url => 'http://some/resource', :headers => {}))
      RestClient.delete('http://some/resource')
    end

    it "HEAD" do
      RestClient::Request.should_receive(:execute).with(hash_including(:method => :head, :url => 'http://some/resource', :headers => {}))
      RestClient.head('http://some/resource')
    end

    it "OPTIONS" do
      RestClient::Request.should_receive(:execute).with(hash_including(:method => :options, :url => 'http://some/resource', :headers => {}))
      RestClient.options('http://some/resource')
    end
  end

  describe "logging" do
    after do
      RestClient.log = nil
    end

    it "uses << if the log is not a string" do
      log = RestClient.log = []
      log.should_receive(:<<).with('xyz')
      RestClient.log << 'xyz'
    end

    it "displays the log to stdout" do
      RestClient.log = 'stdout'
      STDOUT.should_receive(:puts).with('xyz')
      RestClient.log << 'xyz'
    end

    it "displays the log to stderr" do
      RestClient.log = 'stderr'
      STDERR.should_receive(:puts).with('xyz')
      RestClient.log << 'xyz'
    end

    it "append the log to the requested filename" do
      RestClient.log = '/tmp/restclient.log'
      f = mock('file handle')
      File.should_receive(:open).with('/tmp/restclient.log', 'a').and_yield(f)
      f.should_receive(:puts).with('xyz')
      RestClient.log << 'xyz'
    end
  end

end
