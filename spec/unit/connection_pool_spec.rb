# frozen_string_literal: true

require_relative '_lib'

# Minimal stand-in for a started Net::HTTP connection.
class PoolTestConnection
  attr_reader :start_count, :finish_count

  def initialize
    @started = false
    @start_count = 0
    @finish_count = 0
  end

  def started?
    @started
  end

  def start
    @started = true
    @start_count += 1
    self
  end

  def finish
    @started = false
    @finish_count += 1
    self
  end
end

describe Contractful::ConnectionPool do
  subject(:pool) { described_class.new(max_idle: 2) }

  # Builders in real usage always hand back started connections.
  def new_conn
    PoolTestConnection.new.tap(&:start)
  end

  it 'requires a builder block on checkout' do
    expect { pool.checkout('key') }.to raise_error(ArgumentError)
  end

  it 'validates max_idle' do
    expect { described_class.new(max_idle: -1) }.to raise_error(ArgumentError)
    expect { described_class.new(max_idle: 'many') }.to raise_error(ArgumentError)
    expect(described_class.new(max_idle: 0).max_idle).to eq 0
  end

  it 'reuses a checked-in connection for the same key' do
    first = pool.checkout('key') { new_conn }
    pool.checkin('key', first)

    second = pool.checkout('key') { new_conn }
    expect(second).to equal(first)
    expect(pool.stats).to eq(idle: 0, checked_out: 1)
  end

  it 'builds separate connections for different keys' do
    a = pool.checkout('a') { new_conn }
    b = pool.checkout('b') { new_conn }

    expect(b).not_to equal(a)
    expect(pool.stats).to eq(idle: 0, checked_out: 2)
  end

  it 'closes connections beyond max_idle on checkin' do
    conns = Array.new(3) { pool.checkout('key') { new_conn } }
    conns.each { |conn| pool.checkin('key', conn) }

    expect(conns[0].finish_count).to eq(0)
    expect(conns[1].finish_count).to eq(0)
    expect(conns[2].finish_count).to eq(1)
    expect(pool.stats).to eq(idle: 2, checked_out: 0)
  end

  it 'never returns invalidated connections' do
    conn = pool.checkout('key') { new_conn }
    pool.invalidate('key', conn)
    expect(conn.finish_count).to eq(1)

    fresh = pool.checkout('key') { new_conn }
    expect(fresh).not_to equal(conn)
  end

  it 'closes all idle connections on clear!' do
    conns = Array.new(2) { pool.checkout('key') { new_conn } }
    conns.each { |conn| pool.checkin('key', conn) }

    pool.clear!
    expect(conns.all? { |conn| conn.finish_count == 1 }).to be true

    fresh = pool.checkout('key') { new_conn }
    expect(fresh).not_to equal(conns[0])
  end

  it 'builds a new connection when an idle one cannot be revived' do
    conn = pool.checkout('key') { new_conn }
    pool.checkin('key', conn)

    # Simulate the connection dying while idle and failing to restart.
    conn.finish
    def conn.start
      raise IOError, 'broken pipe'
    end

    fresh = pool.checkout('key') { new_conn }
    expect(fresh).not_to equal(conn)
  end

  it 'never shares a connection between concurrent checkouts' do
    conns = []
    threads = 2.times.map do
      Thread.new do
        conn = pool.checkout('key') { new_conn }
        sleep 0.02 # encourage overlap
        conns << conn
        pool.checkin('key', conn)
      end
    end
    threads.each(&:join)

    expect(conns.uniq.size).to eq(2)
    expect(pool.stats).to eq(idle: 2, checked_out: 0)
  end
end
