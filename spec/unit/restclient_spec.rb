require_relative '_lib'

describe RestClient do
  describe "API" do
    %w(get delete head options).each do |verb|
      it verb.to_s.upcase do
        RestClient::Request.should_receive(:execute).with(:method => verb.to_sym, :url => 'http://some/resource', :headers => {})
        RestClient.send(verb.to_sym, 'http://some/resource')
      end
    end

    %w(post put patch).each do |verb|
      it verb.to_s.upcase do
        RestClient::Request.should_receive(:execute).with(:method => verb.to_sym, :url => 'http://some/resource', :payload => 'payload', :headers => {})
        RestClient.send(verb.to_sym, 'http://some/resource', 'payload')
      end
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
      f = double('file handle')
      File.should_receive(:open).with('/tmp/restclient.log', 'a').and_yield(f)
      f.should_receive(:puts).with('xyz')
      RestClient.log << 'xyz'
    end
  end

  describe 'version' do
    it 'has a version ~> 2.0.0.alpha' do
      ver = Gem::Version.new(RestClient.version)
      Gem::Requirement.new('~> 2.0.0.alpha').should be_satisfied_by(ver)
    end
  end
end
