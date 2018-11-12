require_relative '_lib'

describe RestClient2 do
  describe "API" do
    it "GET" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :get, :url => 'http://some/resource', :headers => {})
      RestClient2.get('http://some/resource')
    end

    it "POST" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :post, :url => 'http://some/resource', :payload => 'payload', :headers => {})
      RestClient2.post('http://some/resource', 'payload')
    end

    it "PUT" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :put, :url => 'http://some/resource', :payload => 'payload', :headers => {})
      RestClient2.put('http://some/resource', 'payload')
    end

    it "PATCH" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :patch, :url => 'http://some/resource', :payload => 'payload', :headers => {})
      RestClient2.patch('http://some/resource', 'payload')
    end

    it "DELETE" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :delete, :url => 'http://some/resource', :headers => {})
      RestClient2.delete('http://some/resource')
    end

    it "HEAD" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :head, :url => 'http://some/resource', :headers => {})
      RestClient2.head('http://some/resource')
    end

    it "OPTIONS" do
      expect(RestClient2::Request).to receive(:execute).with(:method => :options, :url => 'http://some/resource', :headers => {})
      RestClient2.options('http://some/resource')
    end
  end

  describe "logging" do
    after do
      RestClient2.log = nil
    end

    it "uses << if the log is not a string" do
      log = RestClient2.log = []
      expect(log).to receive(:<<).with('xyz')
      RestClient2.log << 'xyz'
    end

    it "displays the log to stdout" do
      RestClient2.log = 'stdout'
      expect(STDOUT).to receive(:puts).with('xyz')
      RestClient2.log << 'xyz'
    end

    it "displays the log to stderr" do
      RestClient2.log = 'stderr'
      expect(STDERR).to receive(:puts).with('xyz')
      RestClient2.log << 'xyz'
    end

    it "append the log to the requested filename" do
      RestClient2.log = '/tmp/restclient2.log'
      f = double('file handle')
      expect(File).to receive(:open).with('/tmp/restclient2.log', 'a').and_yield(f)
      expect(f).to receive(:puts).with('xyz')
      RestClient2.log << 'xyz'
    end
  end

  describe 'version' do
    # test that there is a sane version number to avoid accidental 0.0.0 again
    it 'has a version > 2.0.0.alpha, < 3.0' do
      ver = Gem::Version.new(RestClient2.version)
      expect(Gem::Requirement.new('> 2.0.0.alpha', '< 3.0')).to be_satisfied_by(ver)
    end
  end
end
