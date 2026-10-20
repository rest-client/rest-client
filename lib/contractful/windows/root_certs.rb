# frozen_string_literal: true

require 'openssl'
require 'ffi'

# Adapted from Puppet, Copyright (c) Puppet Labs Inc,
# licensed under the Apache License, Version 2.0.
#
# https://github.com/puppetlabs/puppet/blob/bbe30e0a/lib/puppet/util/windows/root_certs.rb

# Represents a collection of trusted root certificates.
#
# @api public
class Contractful::Windows::RootCerts
  include Enumerable
  extend FFI::Library

  typedef :ulong, :dword
  typedef :uintptr_t, :handle

  def initialize(roots)
    @roots = roots
  end

  # Enumerates each root certificate.
  # @yieldparam cert [OpenSSL::X509::Certificate] each root certificate
  # @api public
  def each(&block)
    @roots.each(&block)
  end

  # Returns a new instance.
  # @return [Contractful::Windows::RootCerts] object constructed from current root certificates
  def self.instance
    new(load_certs)
  end

  # Returns an array of root certificates.
  #
  # @return [Array<[OpenSSL::X509::Certificate]>] an array of root certificates
  # @api private
  def self.load_certs
    certs = []

    # This is based on a patch submitted to openssl:
    # http://www.mail-archive.com/openssl-dev@openssl.org/msg26958.html
    ptr = FFI::Pointer::NULL
    store = CertOpenSystemStoreA(nil, 'ROOT')
    begin
      while (ptr = CertEnumCertificatesInStore(store, ptr)) and !ptr.null?
        context = CertContext.new(ptr)
        cert_buf = context[:pbCertEncoded].read_bytes(context[:cbCertEncoded])
        begin
          certs << OpenSSL::X509::Certificate.new(cert_buf)
        rescue StandardError => e
          warn("Failed to import root certificate: #{e.inspect}")
        end
      end
    ensure
      CertCloseStore(store, 0)
    end

    certs
  end

  # typedef ULONG_PTR HCRYPTPROV_LEGACY;
  # typedef void *HCERTSTORE;

  # FFI mapping of the Windows CERT_CONTEXT structure returned by
  # CertEnumCertificatesInStore.
  class CertContext < FFI::Struct
    layout(
      :dwCertEncodingType, :dword,
      :pbCertEncoded,      :pointer,
      :cbCertEncoded,      :dword,
      :pCertInfo,          :pointer,
      :hCertStore,         :handle
    )
  end

  # HCERTSTORE
  # WINAPI
  # CertOpenSystemStoreA(
  #   __in_opt HCRYPTPROV_LEGACY hProv,
  #   __in LPCSTR szSubsystemProtocol
  #   );
  ffi_lib :crypt32
  attach_function :CertOpenSystemStoreA, %i[pointer string], :handle

  # PCCERT_CONTEXT
  # WINAPI
  # CertEnumCertificatesInStore(
  #   __in HCERTSTORE hCertStore,
  #   __in_opt PCCERT_CONTEXT pPrevCertContext
  #   );
  ffi_lib :crypt32
  attach_function :CertEnumCertificatesInStore, %i[handle pointer], :pointer

  # BOOL
  # WINAPI
  # CertCloseStore(
  #   __in_opt HCERTSTORE hCertStore,
  #   __in DWORD dwFlags
  #   );
  ffi_lib :crypt32
  attach_function :CertCloseStore, %i[handle dword], :bool
end
