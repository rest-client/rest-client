# frozen_string_literal: true

require_relative '_lib'

describe Contractful do
  describe 'API' do
    it 'GET' do
      expect(Contractful::Request).to receive(:execute).with(method: :get, url: 'http://some/resource', headers: {})
      Contractful.get('http://some/resource')
    end

    it 'POST' do
      expect(Contractful::Request).to receive(:execute).with(method: :post, url: 'http://some/resource', payload: 'payload', headers: {})
      Contractful.post('http://some/resource', 'payload')
    end

    it 'PUT' do
      expect(Contractful::Request).to receive(:execute).with(method: :put, url: 'http://some/resource', payload: 'payload', headers: {})
      Contractful.put('http://some/resource', 'payload')
    end

    it 'PATCH' do
      expect(Contractful::Request).to receive(:execute).with(method: :patch, url: 'http://some/resource', payload: 'payload', headers: {})
      Contractful.patch('http://some/resource', 'payload')
    end

    it 'DELETE' do
      expect(Contractful::Request).to receive(:execute).with(method: :delete, url: 'http://some/resource', headers: {})
      Contractful.delete('http://some/resource')
    end

    it 'HEAD' do
      expect(Contractful::Request).to receive(:execute).with(method: :head, url: 'http://some/resource', headers: {})
      Contractful.head('http://some/resource')
    end

    it 'OPTIONS' do
      expect(Contractful::Request).to receive(:execute).with(method: :options, url: 'http://some/resource', headers: {})
      Contractful.options('http://some/resource')
    end
  end

  describe 'logging' do
    after do
      Contractful.log = nil
    end

    it 'uses << if the log is not a string' do
      log = Contractful.log = []
      expect(log).to receive(:<<).with('xyz')
      Contractful.log << 'xyz'
    end

    it 'displays the log to stdout' do
      Contractful.log = 'stdout'
      expect { Contractful.log << 'xyz' }.to output("xyz\n").to_stdout
    end

    it 'displays the log to stderr' do
      Contractful.log = 'stderr'
      expect { Contractful.log << 'xyz' }.to output("xyz\n").to_stderr
    end

    it 'append the log to the requested filename' do
      Contractful.log = '/tmp/contractful.log'
      f = double('file handle')
      expect(File).to receive(:open).with('/tmp/contractful.log', 'a').and_yield(f)
      expect(f).to receive(:puts).with('xyz')
      Contractful.log << 'xyz'
    end
  end

  describe 'version' do
    # test that there is a sane version number to avoid accidental 0.0.0 again
    it 'is a parseable, non-prerelease x.y.z version above 0.0.0' do
      ver = Gem::Version.new(Contractful.version)
      expect(ver.to_s).to match(/\A\d+\.\d+\.\d+\z/)
      expect(ver.prerelease?).to be(false)
      expect(ver).to be > Gem::Version.new('0.0.0')
    end
  end
end
