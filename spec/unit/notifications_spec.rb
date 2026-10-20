# frozen_string_literal: true

require_relative '../spec_helper'
require 'stringio'

RSpec.describe Contractful::Notifications do
  before { described_class.clear! }
  after { described_class.clear! }

  describe '.subscribe' do
    it 'requires a block' do
      expect { described_class.subscribe }.to raise_error(ArgumentError, /block is required/)
    end

    it 'returns an unsubscribe handle that detaches the subscriber' do
      events = []
      unsub = described_class.subscribe { |e| events << e }
      expect(described_class.subscriber_count).to eq 1

      unsub.call
      expect(described_class.subscriber_count).to eq 0
    end
  end

  describe '.post' do
    it 'fans events out with a frozen name, payload and monotonic timestamp' do
      events = []
      described_class.subscribe { |e| events << e }

      described_class.post(:retry, attempt: 2, delay: 0.5)

      expect(events.size).to eq 1
      expect(events.first[:name]).to eq 'retry'
      expect(events.first[:payload]).to eq(attempt: 2, delay: 0.5)
      expect(events.first[:payload]).to be_frozen
      expect(events.first[:at]).to be_a(Float)
    end

    it 'never lets a raising subscriber break the poster' do
      raised = false
      described_class.subscribe { raise 'boom' }
      described_class.subscribe { raised = true }

      expect { described_class.post('request') }.not_to raise_error
      expect(raised).to be true
    end

    it 'logs subscriber failures when Contractful.log is set' do
      sink = StringIO.new
      Contractful.log = sink
      described_class.subscribe { raise ArgumentError, 'nope' }

      described_class.post('request')

      expect(sink.string).to include('notification subscriber raised ArgumentError: nope')
    end
  end
end

RSpec.describe 'request pipeline notifications' do
  include Helpers

  before do
    Contractful::Notifications.clear!
    subscribe
  end

  after { Contractful::Notifications.clear! }

  let(:events) { [] }
  let(:subscribe) { Contractful::Notifications.subscribe { |e| events << e } }
  let(:opts) { {} }

  def run_get(url = 'http://example.com/resource')
    Contractful::Request.execute(method: :get, url: url, **opts)
  end

  context 'on a successful request' do
    before do
      stub_request(:get, 'http://example.com/resource').to_return(body: 'ok')
    end

    it 'posts request and response events with status and duration' do
      run_get

      names = events.map { |e| e[:name] }
      expect(names).to eq %w[request response]
      expect(events.first[:payload]).to include(method: 'get', url: 'http://example.com/resource', attempt: 1)
      expect(events.last[:payload]).to include(status: 200)
      expect(events.last[:payload][:duration_ms]).to be_a(Float)
    end

    it 'redacts URL passwords from request and response events' do
      url = 'http://alice:s3cr3t@example.com/resource'
      stub_request(:get, url).to_return(body: 'ok')

      run_get(url)

      urls = events.map { |e| e[:payload][:url] }
      expect(urls).to all(eq('http://alice:REDACTED@example.com/resource'))
    end
  end

  context 'on a retried network failure' do
    let(:opts) { { max_retries: 1, retry_interval: 0 } }

    before do
      stub = stub_request(:get, 'http://example.com/resource').to_raise(EOFError)
      stub.then.to_return(body: 'recovered')
    end

    it 'posts a retry event with the classified error name and the delay' do
      run_get

      retry_event = events.find { |e| e[:name] == 'retry' }
      expect(retry_event[:payload]).to include(attempt: 1, cause: 'Contractful::ServerBrokeConnection', delay: 0)
      expect(events.last[:name]).to eq 'response'
      expect(events.last[:payload][:status]).to eq 200
    end
  end

  context 'on a retried HTTP error status' do
    let(:opts) { { max_retries: 1, retry_interval: 0, retry_after: true } }

    before do
      stub_request(:get, 'http://example.com/resource')
        .to_return(status: 503).then.to_return(body: 'back')
    end

    it 'posts a retry event carrying the HTTP status as the cause' do
      run_get

      retry_event = events.find { |e| e[:name] == 'retry' }
      expect(retry_event[:payload][:cause]).to eq 503
    end
  end

  context 'on a terminal failure' do
    before do
      stub_request(:get, 'http://example.com/resource').to_return(status: 404)
    end

    it 'still posts the response event for the failed response' do
      expect { run_get }.to raise_error(Contractful::ResourceNotFound)

      response_event = events.find { |e| e[:name] == 'response' }
      expect(response_event[:payload][:status]).to eq 404
    end
  end
end
