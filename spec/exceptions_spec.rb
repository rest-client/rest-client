require File.dirname(__FILE__) + '/base'

describe RestClient::Exception do
	it "sets the exception message to ErrorMessage" do
		RestClient::ResourceNotFound.new.message.should == 'Resource not found'
	end

	it "contains exceptions in RestClient" do
		RestClient::Unauthorized.new.should be_a_kind_of(RestClient::Exception)
		RestClient::ServerBrokeConnection.new.should be_a_kind_of(RestClient::Exception)
	end
end

describe RestClient::RequestFailed do
	it "stores the http response on the exception" do
		begin
			raise RestClient::RequestFailed, :response
		rescue RestClient::RequestFailed => e
			e.response.should == :response
		end
	end

	it "http_code convenience method for fetching the code as an integer" do
		RestClient::RequestFailed.new(mock('res', :code => '502')).http_code.should == 502
	end

	it "shows the status code in the message" do
		RestClient::RequestFailed.new(mock('res', :code => '502')).to_s.should match(/502/)
	end
end

describe RestClient::ResourceNotFound do
	it "also has the http response attached" do
		begin
			raise RestClient::ResourceNotFound, :response
		rescue RestClient::ResourceNotFound => e
			e.response.should == :response
		end
	end
end

describe "backwards compatibility" do
	it "alias RestClient::Request::Redirect to RestClient::Redirect" do
		RestClient::Request::Redirect.should == RestClient::Redirect
	end

	it "alias RestClient::Request::Unauthorized to RestClient::Unauthorized" do
		RestClient::Request::Unauthorized.should == RestClient::Unauthorized
	end

	it "alias RestClient::Request::RequestFailed to RestClient::RequestFailed" do
		RestClient::Request::RequestFailed.should == RestClient::RequestFailed
	end
end
