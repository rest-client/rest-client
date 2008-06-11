require File.dirname(__FILE__) + '/base'

describe RestClient::RequestFailed do
	before do
		@error = RestClient::RequestFailed.new(nil)
	end

	it "extracts the error message from xml" do
		@error.response = mock('response', :code => '422', :body => '<errors><error>Error 1</error><error>Error 2</error></errors>')
		@error.message.should == 'Error 1 / Error 2'
	end

	it "ignores responses without xml since they might contain sensitive data" do
		@error.response = mock('response', :code => '500', :body => 'Syntax error in SQL query: SELECT * FROM ...')
		@error.message.should == 'Unknown error'
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