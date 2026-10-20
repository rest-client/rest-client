# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Contractful::RateLimit do
  describe '.from_headers' do
    it 'parses the IETF RateLimit-* headers' do
      info = described_class.from_headers(
        ratelimit_limit: '100, 100;w=1',
        ratelimit_remaining: '97',
        ratelimit_reset: '30',
        ratelimit_policy: '100;w=1;comment="per minute"'
      )

      expect(info.limit).to eq 100
      expect(info.remaining).to eq 97
      expect(info.policy).to eq '100;w=1;comment="per minute"'
      expect(info.reset).to be_within(1.5).of(Time.now + 30)
    end

    it 'parses the legacy X-RateLimit-* headers (epoch reset)' do
      info = described_class.from_headers(
        x_ratelimit_limit: '5000',
        x_ratelimit_remaining: '4998',
        x_ratelimit_reset: '1800000000'
      )

      expect(info.limit).to eq 5000
      expect(info.remaining).to eq 4998
      expect(info.reset).to eq Time.at(1_800_000_000)
      expect(info.policy).to be_nil
    end
    it 'prefers the IETF spelling when both conventions are present' do
      info = described_class.from_headers(
        ratelimit_limit: '100',
        x_ratelimit_limit: '999',
        ratelimit_remaining: '42',
        x_ratelimit_remaining: '7'
      )

      expect(info.limit).to eq 100
      expect(info.remaining).to eq 42
    end

    it 'accepts an HTTP-date IETF reset' do
      info = described_class.from_headers(
        ratelimit_reset: 'Wed, 21 Oct 2026 07:28:00 GMT'
      )
      expect(info.reset).to eq Time.httpdate('Wed, 21 Oct 2026 07:28:00 GMT')
    end

    it 'returns nil when the server sends no rate-limit headers' do
      expect(described_class.from_headers({ 'content_type' => 'application/json' })).to be_nil
      expect(described_class.from_headers(nil)).to be_nil
    end

    it 'normalizes array header values' do
      info = described_class.from_headers(x_ratelimit_limit: ['60'])
      expect(info.limit).to eq 60
    end
  end

  describe 'quota state helpers' do
    it 'reports exhaustion at zero remaining' do
      expect(described_class.from_headers(x_ratelimit_remaining: '0').exhausted?).to be true
      expect(described_class.from_headers(x_ratelimit_remaining: '3').exhausted?).to be false
      expect(described_class.from_headers(x_ratelimit_limit: '10').exhausted?).to be false
    end

    it 'computes reset_in, clamping past dates to zero' do
      past = described_class.new(reset: Time.now - 10)
      expect(past.reset_in).to eq 0.0

      soon = described_class.new(reset: Time.now + 12.4)
      expect(soon.reset_in).to be_between(11.0, 12.5)
      expect(described_class.new.reset_in).to be_nil
    end

    it 'summarizes itself' do
      info = described_class.from_headers(
        ratelimit_limit: '100', ratelimit_remaining: '97', ratelimit_reset: '30'
      )
      expect(info.to_s).to match(%r{97/100.*resets in})
      expect(info.inspect).to include('remaining=97')
    end
  end
end

RSpec.describe 'response rate-limit integration' do
  it 'exposes parsed rate-limit info on responses' do
    stub_request(:get, 'http://some/resource')
      .to_return(body: 'ok', headers: {
                   'RateLimit-Limit' => '100',
                   'RateLimit-Remaining' => '98',
                   'RateLimit-Reset' => '60'
                 })

    response = Contractful.get('http://some/resource')
    expect(response.rate_limit).to be_a(Contractful::RateLimit)
    expect(response.rate_limit.remaining).to eq 98
    expect(response.rate_limited?).to be false
  end

  it 'returns nil rate_limit when the server sends no headers' do
    stub_request(:get, 'http://some/resource').to_return(body: 'ok')

    response = Contractful.get('http://some/resource')
    expect(response.rate_limit).to be_nil
    expect(response.rate_limited?).to be false
  end

  it 'flags rate_limited? for a 429 even without headers' do
    stub_request(:get, 'http://some/resource').to_return(status: 429, body: '')

    response = Contractful::Request.execute(url: 'http://some/resource',
                                            method: :get) { |r| r }
    expect(response.rate_limited?).to be true
  end

  it 'flags rate_limited? when the reported quota is exhausted' do
    stub_request(:get, 'http://some/resource')
      .to_return(body: 'ok', headers: { 'X-RateLimit-Remaining' => '0' })

    response = Contractful.get('http://some/resource')
    expect(response.rate_limited?).to be true
  end

  it 'falls back to RateLimit-Reset when a 429 has no Retry-After' do
    stub_request(:get, 'http://some/resource')
      .to_return(status: 429, headers: { 'RateLimit-Reset' => '2' })
      .then.to_return(body: 'ok')

    delays = []
    allow_any_instance_of(Contractful::Request).to receive(:sleep_for_retry) do |_, secs|
      delays << secs
    end

    Contractful::Request.execute(url: 'http://some/resource', method: :get,
                                 max_retries: 1, retry_interval: 0.5)
    expect(delays.first).to be_between(1.0, 2.5)
  end
end
