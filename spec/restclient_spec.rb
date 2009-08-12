require File.dirname(__FILE__) + '/base'

describe RestClient do
	describe "API" do
		it "GET" do
			RestClient::Request.should_receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => {})
			RestClient.get('http://some/resource')
		end

		it "POST" do
			RestClient::Request.should_receive(:execute).with(:method => :post, :url => 'http://some/resource', :payload => 'payload', :headers => {})
			RestClient.post('http://some/resource', 'payload')
		end

		it "PUT" do
			RestClient::Request.should_receive(:execute).with(:method => :put, :url => 'http://some/resource', :payload => 'payload', :headers => {})
			RestClient.put('http://some/resource', 'payload')
		end

		it "DELETE" do
			RestClient::Request.should_receive(:execute).with(:method => :delete, :url => 'http://some/resource', :headers => {})
			RestClient.delete('http://some/resource')
		end

		it "HEAD" do
			RestClient::Request.should_receive(:execute).with(:method => :head, :url => 'http://some/resource', :headers => {})
			RestClient.head('http://some/resource')
		end
	end

	describe "logging" do
		after do
			RestClient.log = nil
		end

		it "gets the log source from the RESTCLIENT_LOG environment variable" do
			ENV.stub!(:[]).with('RESTCLIENT_LOG').and_return('from env')
			RestClient.log = 'from class method'
			RestClient.log.should == 'from env'
		end

		it "sets a destination for log output, used if no environment variable is set" do
			ENV.stub!(:[]).with('RESTCLIENT_LOG').and_return(nil)
			RestClient.log = 'from class method'
			RestClient.log.should == 'from class method'
		end

		it "returns nil (no logging) if neither are set (default)" do
			ENV.stub!(:[]).with('RESTCLIENT_LOG').and_return(nil)
			RestClient.log.should == nil
		end
	end
end
