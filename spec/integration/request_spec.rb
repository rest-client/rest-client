# frozen_string_literal: true

require_relative '_lib'

describe Contractful::Request, :live do
  before(:all) do
    WebMock.disable!
  end

  after(:all) do
    WebMock.enable!
  end

  describe 'ssl verification' do
    it 'is successful with the correct ca_file' do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        ssl_ca_file: File.join(File.dirname(__FILE__), 'certs', 'isrg-root-x1.crt')
      )
      expect { request.execute }.not_to raise_error
    end

    it 'is successful with the correct ca_path' do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        ssl_ca_path: File.join(File.dirname(__FILE__), 'capath_isrg')
      )
      expect { request.execute }.not_to raise_error
    end

    # TODO: deprecate and remove Contractful::SSLCertificateNotVerified and just
    # pass through OpenSSL::SSL::SSLError directly. See note in
    # lib/contractful/request.rb.
    #
    # On OS X, this test fails since Apple has patched OpenSSL to always fall
    # back on the system CA store.
    it 'is unsuccessful with an incorrect ca_file', unless: Contractful::Platform.mac_mri? do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        ssl_ca_file: File.join(File.dirname(__FILE__), 'certs', 'verisign.crt')
      )
      expect { request.execute }.to raise_error(Contractful::SSLCertificateNotVerified)
    end

    # On OS X, this test fails since Apple has patched OpenSSL to always fall
    # back on the system CA store.
    it 'is unsuccessful with an incorrect ca_path', unless: Contractful::Platform.mac_mri? do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        ssl_ca_path: File.join(File.dirname(__FILE__), 'capath_verisign')
      )
      expect { request.execute }.to raise_error(Contractful::SSLCertificateNotVerified)
    end

    it 'is successful using the default system cert store' do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        verify_ssl: true
      )
      expect { request.execute }.not_to raise_error
    end

    it 'executes the verify_callback' do
      ran_callback = false
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        verify_ssl: true,
        ssl_verify_callback: lambda { |preverify_ok, _store_ctx|
          ran_callback = true
          preverify_ok
        }
      )
      expect { request.execute }.not_to raise_error
      expect(ran_callback).to eq(true)
    end

    it 'fails verification when the callback returns false',
       unless: Contractful::Platform.mac_mri? do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        verify_ssl: true,
        ssl_verify_callback: ->(_preverify_ok, _store_ctx) { false }
      )
      expect { request.execute }.to raise_error(Contractful::SSLCertificateNotVerified)
    end

    it 'succeeds verification when the callback returns true',
       unless: Contractful::Platform.mac_mri? do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        verify_ssl: true,
        ssl_ca_file: File.join(File.dirname(__FILE__), 'certs', 'verisign.crt'),
        ssl_verify_callback: ->(_preverify_ok, _store_ctx) { true }
      )
      expect { request.execute }.not_to raise_error
    end
  end

  describe 'timeouts' do
    it 'raises OpenTimeout when it hits an open timeout' do
      request = Contractful::Request.new(
        method: :get,
        url: 'http://www.mozilla.org',
        open_timeout: 1e-10
      )
      expect { request.execute }.to(
        raise_error(Contractful::Exceptions::OpenTimeout)
      )
    end

    it 'raises ReadTimeout when it hits a read timeout via :read_timeout' do
      request = Contractful::Request.new(
        method: :get,
        url: 'https://www.mozilla.org',
        read_timeout: 1e-10
      )
      expect { request.execute }.to(
        raise_error(Contractful::Exceptions::ReadTimeout)
      )
    end
  end
end
