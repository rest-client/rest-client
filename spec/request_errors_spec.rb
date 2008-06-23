require File.dirname(__FILE__) + '/base'

describe RestClient::RequestFailed do
	before do
		@error = RestClient::RequestFailed.new
	end

	it "extracts the error message from xml" do
		@error.response = mock('response', :code => '422', :body => '<errors><error>Error 1</error><error>Error 2</error></errors>')
		@error.message.should == 'Error 1 / Error 2'
	end

	it "ignores responses without xml since they might contain sensitive data" do
		@error.response = mock('response', :code => '500', :body => 'Syntax error in SQL query: SELECT * FROM ...')
		@error.message.should == 'Unknown error, HTTP status code 500'
	end

	it "accepts a default error message" do
		@error.response = mock('response', :code => '500', :body => 'Internal Server Error')
		@error.message('Custom default message').should == 'Custom default message'
	end

	it "doesn't show the default error message when there's something in the xml" do
		@error.response = mock('response', :code => '422', :body => '<errors><error>Specific error message</error></errors>')
		@error.message('Custom default message').should == 'Specific error message'
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
