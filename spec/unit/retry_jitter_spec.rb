# frozen_string_literal: true

require_relative '../spec_helper'

# Retry-jitter behavior: styles, bounds, injectable randomness, validation,
# and the guarantee that server-provided Retry-After delays are never
# jittered. Deterministic throughout via seeded Random sources.
RSpec.describe Contractful::Request do
  let(:url) { 'http://example.com/resource' }

  def request(**opts)
    described_class.new(method: :get, url: url, **opts)
  end

  describe 'option validation' do
    it 'rejects an unknown jitter style' do
      expect { request(retry_jitter: :chaotic) }.to raise_error(
        ArgumentError, /:retry_jitter must be false, :full, :equal or :decorrelated/
      )
    end

    it 'rejects a non-positive cap' do
      expect do
        request(retry_jitter_cap: 0)
      end.to raise_error(ArgumentError, /:retry_jitter_cap must be a positive Numeric/)
    end

    it 'rejects an rng that does not answer rand' do
      expect { request(retry_rng: 'nope') }.to raise_error(ArgumentError, /:retry_rng must respond to #rand/)
    end
  end

  describe '#retry_backoff_delay' do
    it 'returns the plain exponential backoff when jitter is disabled (default)' do
      r = request(retry_interval: 0.5)
      expect(r.send(:retry_backoff_delay, 1)).to eq 0.5
      expect(r.send(:retry_backoff_delay, 3)).to eq 2.0
    end

    it 'draws :full jitter from [0, backoff]' do
      first = request(retry_interval: 1.0, retry_jitter: :full, retry_rng: Random.new(7)).send(:retry_backoff_delay, 2)
      expect(first).to be_between(0, 2.0).inclusive
      # deterministic under the seed: a fresh rng replays the same draw
      replay = request(retry_interval: 1.0, retry_jitter: :full, retry_rng: Random.new(7)).send(:retry_backoff_delay, 2)
      expect(replay).to eq first
    end

    it 'draws :equal jitter from [backoff, 2 * backoff]' do
      r = request(retry_interval: 1.0, retry_jitter: :equal, retry_rng: Random.new(11))
      expect(r.send(:retry_backoff_delay, 2)).to be_between(2.0, 4.0).inclusive
    end

    it 'draws :decorrelated jitter within [base, cap] and honors the cap' do
      r = request(retry_interval: 0.5, retry_jitter: :decorrelated,
                  retry_jitter_cap: 2.0, retry_rng: Random.new(3))
      20.times { expect(r.send(:retry_backoff_delay, 4)).to be_between(0.5, 2.0).inclusive }
    end

    it 'keeps zero delays at zero under any jitter style' do
      r = request(retry_interval: 0, retry_jitter: :full, retry_rng: Random.new(1))
      expect(r.send(:retry_backoff_delay, 2)).to eq 0
    end
  end

  describe 'end-to-end timing' do
    it 'uses the jittered delay for network-error retries but not for Retry-After' do
      delays = []
      r = request(retry_interval: 1.0, max_retries: 1, retry_jitter: :equal, retry_rng: Random.new(5))

      # delay path 1: computed backoff
      stub_request(:get, url).to_raise(EOFError).then.to_return(body: 'ok')
      allow(r).to receive(:sleep_for_retry) { |s| delays << s }
      r.execute
      expect(delays.first).to be_between(1.0, 2.0).inclusive
    end

    it 'honors an exact Retry-After delay without jittering it' do
      delays = []
      r = request(max_retries: 1, retry_jitter: :equal, retry_rng: Random.new(5), retry_after: true)

      stub_request(:get, url).to_return(status: 503, headers: { 'Retry-After' => '7' })
                             .then.to_return(body: 'ok')
      allow(r).to receive(:sleep_for_retry) { |s| delays << s }
      r.execute
      expect(delays).to include(7)
    end
  end

  describe 'contract-layer pass-through' do
    it 'accepts _retry_jitter meta options' do
      client = Class.new do
        include Contractful::Contract

        base 'http://example.com'
        contract :ping, 'GET /ping' do
          responds 200
        end
      end.new

      stub_request(:get, 'http://example.com/ping').to_return(body: 'pong')
      expect(client.ping(_retry_jitter: :full, _retry_rng: Random.new(2))).to be_a(String)
    end
  end
end
