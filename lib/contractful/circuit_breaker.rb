# frozen_string_literal: true

module Contractful
  # Raised instead of sending a request when the circuit for the target
  # host is open. Not retryable within the same call — the breaker exists
  # precisely to stop hammering a host that is failing; back off at a
  # higher level and try again after the cooldown.
  # (Contractful::Exception is itself a RuntimeError; the cop's literal
  # lint on '< Exception' does not see through the constant.)
  class CircuitOpenError < Exception # rubocop:disable Lint/InheritException
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

  # A host-level circuit breaker (closed → open → half-open → closed).
  #
  # Counted as failures: network errors from {Request::RETRIABLE_EXCEPTIONS}
  # and responses carrying a retryable status (408/425/429/5xx — see
  # {Exceptions::RETRIABLE_STATUSES}). Everything else, including 4xx
  # client errors, is a success: a circuit must not open because a caller
  # keeps asking for a missing resource.
  #
  # Breakers are process-wide, keyed by scheme/host/port and guarded by a
  # mutex; while half-open, requests are allowed through and each outcome
  # decides the next state. State transitions post a `circuit` event to
  # {Notifications} with the key and both states.
  #
  # Opt in per request with `breaker: true` (defaults) or
  # `breaker: { threshold: 5, cooldown: 30 }`:
  #
  #   Contractful.get('https://api.example.com/x', breaker: true)
  #
  # After `threshold` consecutive failures the circuit opens and every
  # request to that host fails fast with {CircuitOpenError} for `cooldown`
  # seconds; the next request after the cooldown probes the host
  # (half-open) and its outcome closes or re-opens the circuit. Failures
  # are counted per logical request — the retry layer inside a request is
  # already absorbing transient errors, so only a request that ultimately
  # failed counts.
  class CircuitBreaker
    DEFAULT_THRESHOLD = 5
    DEFAULT_COOLDOWN = 30.0

    CLOCK = Process::CLOCK_MONOTONIC

    attr_reader :key, :threshold, :cooldown

    def initialize(key, threshold: DEFAULT_THRESHOLD, cooldown: DEFAULT_COOLDOWN)
      raise ArgumentError, 'threshold must be a positive Integer' unless threshold.is_a?(Integer) && threshold.positive?
      raise ArgumentError, 'cooldown must be a positive Numeric' unless cooldown.is_a?(Numeric) && cooldown.positive?

      @key = key
      @threshold = threshold
      @cooldown = cooldown
      @state = :closed
      @failures = 0
      @opened_at = nil
      @mutex = Mutex.new
    end

    # Current state, lazily transitioning open → half-open once the
    # cooldown has elapsed. Notifications are posted after releasing the
    # lock so that subscribers may safely inspect the breaker.
    def state
      from, current = @mutex.synchronize { advance_open_state }
      post_transition(from, :half_open) if from
      current
    end

    # Raise {CircuitOpenError} if the circuit is open; otherwise allow the
    # request (a half-open circuit lets the probe through).
    def check!
      from = nil
      error = @mutex.synchronize do
        from, = advance_open_state
        @state == :open ? open_error : nil
      end
      post_transition(from, :half_open) if from
      raise error if error
    end

    def record_success
      from = nil
      @mutex.synchronize do
        from = @state unless @state == :closed
        @state = :closed
        @failures = 0
        @opened_at = nil
      end
      post_transition(from, :closed) if from
      nil
    end

    def record_failure
      from = @mutex.synchronize { count_failure! }
      post_transition(from, :open) if from
      nil
    end

    # Judge a transmitted response: retryable statuses are failures,
    # everything else (4xx included) is a success. An unknown result (for
    # example the raw `block_response` path, which has no Response object)
    # is not evidence of success and leaves the breaker unchanged.
    def record_response(response)
      return unless response.respond_to?(:code)

      code = response.code.to_i
      return if code.zero?

      if Exceptions.retryable?(code)
        record_failure
      else
        record_success
      end
    end

    class << self
      # Process-wide registry; breaker_for lazily creates one breaker per
      # scheme/host/port key.
      def registry
        @registry ||= Registry.new
      end
    end

    # Lazily-materializing breaker store. The first configuration for an
    # origin wins: later calls for the same scheme/host/port reuse the
    # existing breaker and ignore their threshold/cooldown options.
    class Registry
      def initialize
        @breakers = {}
        @mutex = Mutex.new
      end

      def breaker_for(uri, threshold: DEFAULT_THRESHOLD, cooldown: DEFAULT_COOLDOWN)
        key = "#{uri.scheme}://#{uri.host}:#{uri.port}"
        @mutex.synchronize do
          @breakers[key] ||= CircuitBreaker.new(key, threshold: threshold, cooldown: cooldown)
        end
      end

      def clear!
        @mutex.synchronize { @breakers.clear }
      end

      def size
        @mutex.synchronize { @breakers.size }
      end
    end

    private

    # Move an expired open circuit to half-open. Must be called with the
    # mutex held; returns the previous state (nil when no transition) and
    # the resulting state.
    def advance_open_state
      return [nil, @state] unless @state == :open && cooldown_elapsed?

      from = @state
      @state = :half_open
      @opened_at = nil
      [from, @state]
    end

    # Count a failure and open the circuit at the threshold. Must be called
    # with the mutex held; returns the previous state when it opened.
    def count_failure!
      @failures += 1
      return nil unless @state == :half_open || @failures >= @threshold

      from = @state
      @state = :open
      @opened_at = Process.clock_gettime(CLOCK)
      @failures = 0
      from
    end

    def open_error
      CircuitOpenError.new(
        "circuit open for #{@key} " \
        "(retry after #{remaining_cooldown.round(1)}s)"
      )
    end

    def cooldown_elapsed?
      @opened_at && (Process.clock_gettime(CLOCK) - @opened_at) >= @cooldown
    end

    def remaining_cooldown
      left = @cooldown - (Process.clock_gettime(CLOCK) - @opened_at)
      left.positive? ? left : 0.0
    end

    def post_transition(from, to)
      Notifications.post('circuit', key: @key, from: from, state: to)
    end
  end
end
