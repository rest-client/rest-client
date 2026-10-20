# frozen_string_literal: true

module Contractful
  # Raised when the pacing budget would force a wait longer than the
  # configured `max_wait` — fail loudly instead of sleeping unboundedly.
  # (Contractful::Exception is itself a RuntimeError; the cop's literal
  # lint on '< Exception' does not see through the constant.)
  class PacingTimeout < Exception # rubocop:disable Lint/InheritException
    # The base Contractful::Exception#initialize takes a response object,
    # not a message — take the message explicitly.
    def initialize(message = nil)
      super()
      @message = message
    end

    def retryable?
      false
    end
  end

  # Proactive rate-limit enforcement: a process-wide, thread-safe sliding
  # window that delays (or refuses) requests so a configured per-host quota
  # is never exceeded in the first place — instead of eating 429s and
  # retrying after the fact.
  #
  # Opt in per request with `pace: true` (defaults: 600 requests / 60s
  # window, 30s max wait) or a config Hash:
  #
  #   Contractful::Request.execute(
  #     method: :get, url: 'https://api.example.com/x',
  #     pace: { limit: 100, window: 60, max_wait: 10 }
  #   )
  #
  # Requests are paced per scheme/host/port across the whole process
  # (threads included): each attempt — retries included — must acquire a
  # slot before the request leaves. When the window is full, the request
  # sleeps until the oldest slot expires (posting a `pace` notification
  # with the delay); when that wait would exceed `max_wait`, it raises
  # {PacingTimeout} instead of stalling silently. A sleep in the request
  # path is exactly what pacing means — callers who cannot tolerate it
  # should set a small `max_wait`.
  class Pacer
    DEFAULT_LIMIT = 600
    DEFAULT_WINDOW = 60.0
    DEFAULT_MAX_WAIT = 30.0

    CLOCK = Process::CLOCK_MONOTONIC

    attr_reader :key, :limit, :window, :max_wait

    def initialize(key, limit: DEFAULT_LIMIT, window: DEFAULT_WINDOW, max_wait: DEFAULT_MAX_WAIT)
      raise ArgumentError, 'limit must be a positive Integer' unless limit.is_a?(Integer) && limit.positive?
      raise ArgumentError, 'window must be a positive Numeric' unless window.is_a?(Numeric) && window.positive?
      raise ArgumentError, 'max_wait must be a non-negative Numeric' unless max_wait.is_a?(Numeric) && max_wait >= 0

      @key = key
      @limit = limit
      @window = window
      @max_wait = max_wait
      @stamps = []
      @mutex = Mutex.new
    end

    # Acquire a slot, sleeping (outside the lock) until one frees up. Every
    # actual wait posts a `pace` notification with the delay.
    def acquire
      loop do
        wait = reserve_slot_or_wait
        return if wait <= 0

        enforce_max_wait!(wait)
        Notifications.post('pace', key: @key, delay: wait.round(3),
                                   limit: @limit, window: @window)
        sleep(wait)
      end
    end

    # Requests recorded inside the current window (diagnostics/tests).
    def pending
      @mutex.synchronize do
        now = Process.clock_gettime(CLOCK)
        @stamps.reject! { |t| now - t >= @window }
        @stamps.size
      end
    end

    private

    # Under the lock: expire old slots, take one if the budget allows,
    # otherwise report the wait until the oldest slot expires.
    def reserve_slot_or_wait
      @mutex.synchronize do
        now = Process.clock_gettime(CLOCK)
        @stamps.reject! { |t| now - t >= @window }
        if @stamps.size < @limit
          @stamps << now
          0.0
        else
          @stamps.first + @window - now
        end
      end
    end

    def enforce_max_wait!(wait)
      return if wait <= @max_wait

      raise PacingTimeout,
            "pace limit #{@limit}/#{@window}s for #{@key} would wait " \
            "#{wait.round(1)}s (max_wait #{@max_wait}s)"
    end

    class << self
      # Process-wide registry; pacer_for lazily creates one pacer per
      # scheme/host/port key.
      def registry
        @registry ||= Registry.new
      end
    end

    # Lazily-materializing pacer store. The first configuration for an
    # origin wins: later calls for the same scheme/host/port reuse the
    # existing pacer and ignore their limit/window/max_wait options.
    class Registry
      def initialize
        @pacers = {}
        @mutex = Mutex.new
      end

      def pacer_for(uri, limit: DEFAULT_LIMIT, window: DEFAULT_WINDOW, max_wait: DEFAULT_MAX_WAIT)
        key = "#{uri.scheme}://#{uri.host}:#{uri.port}"
        @mutex.synchronize do
          @pacers[key] ||= Pacer.new(key, limit: limit, window: window, max_wait: max_wait)
        end
      end

      def clear!
        @mutex.synchronize { @pacers.clear }
      end

      def size
        @mutex.synchronize { @pacers.size }
      end
    end
  end
end
