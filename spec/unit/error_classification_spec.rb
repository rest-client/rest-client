# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Contractful::Exceptions error classification' do
  describe 'RETRIABLE_STATUSES' do
    it 'classifies transient statuses as retryable' do
      expect(Contractful::Exceptions::RETRIABLE_STATUSES).to include(408, 425, 429, 500, 502, 503, 504)
    end

    it 'excludes terminal statuses' do
      [400, 401, 403, 404, 409, 422, 501].each do |status|
        expect(Contractful::Exceptions::RETRIABLE_STATUSES).not_to include(status)
      end
    end
  end

  describe 'Exception#retryable?' do
    it 'defaults to terminal (false) for exceptions without a response' do
      expect(Contractful::Exception.new.retryable?).to be false
      expect(Contractful::SSLCertificateNotVerified.new.retryable?).to be false
    end

    it 'classifies response-bearing exceptions by HTTP status' do
      response = double('response', code: 429)
      expect(Contractful::TooManyRequests.new(response).retryable?).to be true

      response = double('response', code: 404)
      expect(Contractful::NotFound.new(response).retryable?).to be false

      response = double('response', code: 503)
      expect(Contractful::ServiceUnavailable.new(response).retryable?).to be true
    end

    it 'marks network timeouts retryable' do
      expect(Contractful::Exceptions::OpenTimeout.new.retryable?).to be true
      expect(Contractful::Exceptions::ReadTimeout.new.retryable?).to be true
      expect(Contractful::ServerBrokeConnection.new.retryable?).to be true
    end
  end

  describe '.retryable?' do
    it 'classifies Integer statuses' do
      expect(Contractful::Exceptions.retryable?(429)).to be true
      expect(Contractful::Exceptions.retryable?(503)).to be true
      expect(Contractful::Exceptions.retryable?(404)).to be false
      expect(Contractful::Exceptions.retryable?(401)).to be false
    end

    it 'classifies Contractful exceptions' do
      expect(Contractful::Exceptions.retryable?(Contractful::Exceptions::OpenTimeout.new)).to be true
      expect(Contractful::Exceptions.retryable?(Contractful::NotFound.new)).to be false
      expect(Contractful::Exceptions.retryable?(Contractful::ServerBrokeConnection.new)).to be true
    end

    it 'classifies plain network errors' do
      expect(Contractful::Exceptions.retryable?(SocketError.new('boom'))).to be true
      expect(Contractful::Exceptions.retryable?(EOFError.new)).to be true
      expect(Contractful::Exceptions.retryable?(Errno::ECONNRESET.new)).to be true
      expect(Contractful::Exceptions.retryable?(Net::OpenTimeout.new)).to be true
    end

    it 'classifies anything else as terminal' do
      expect(Contractful::Exceptions.retryable?(ArgumentError.new('bad arg'))).to be false
      expect(Contractful::Exceptions.retryable?('weird')).to be false
      expect(Contractful::Exceptions.retryable?(nil)).to be false
    end
  end
end
