# frozen_string_literal: true

module Contractful
  # Lightweight in-process event notifications.
  #
  # The request pipeline posts lifecycle events to this hub so callers can
  # build metrics, tracing and alerting without touching the transport:
  #
  #   Contractful::Notifications.subscribe do |event|
  #     statsd.increment("http.#{event[:name]}", tags: event[:payload].slice(:method, :url))
  #   end
  #
  # Events posted by the core:
  #
  # * <tt>request</tt> — method, url, attempt (1-based)
  # * <tt>response</tt> — method, url, status, duration_ms (one per attempt
  #   that produced a response, including suppressed error responses)
  # * <tt>retry</tt> — method, url, attempt, delay (seconds, post-jitter),
  #   cause (exception class name or HTTP status Integer)
  #
  # Resilience features post their own events on top of these (circuit
  # breaker state changes, rate-limit sleeps, token refreshes).
  #
  # Subscribers must never raise: a failing subscriber is logged via
  # {Contractful.log} (when set) and skipped, so observability can never
  # break the request it observes. This module is thread-safe; the
  # subscriber list is guarded by a mutex and posted payloads are frozen.
  #
  # A bridge for ActiveSupport::Notifications ships separately —
  # <tt>require 'contractful/notifications/active_support'</tt> re-posts
  # every event as <tt>contractual.<name></tt> ... see that file.
  module Notifications
    @mutex = Mutex.new
    @subscribers = []

    class << self
      # Subscribe to every event. Returns an unsubscribe Proc; call it to
      # detach the subscriber.
      #
      # @yield [event] every posted event
      # @yieldparam event [Hash] <tt>{name:, payload:, at:}</tt> where +at+
      #   is a monotonic timestamp in seconds
      # @return [Proc] unsubscribe handle
      def subscribe(&block)
        raise ArgumentError, 'a block is required' unless block

        @mutex.synchronize { @subscribers << block }
        -> { unsubscribe(&block) }
      end

      # Remove a specific subscriber block.
      def unsubscribe(&block)
        @mutex.synchronize { @subscribers.delete(block) }
      end

      # Fan an event out to all subscribers. Internal — the request pipeline
      # calls this; application code only subscribes. Never raises.
      #
      # @param name [String, Symbol] event name
      # @param payload [Hash] event attributes (copied and frozen)
      # @return [void]
      def post(name, **payload)
        event = { name: name.to_s, payload: payload.freeze,
                  at: Process.clock_gettime(Process::CLOCK_MONOTONIC) }.freeze
        listeners = @mutex.synchronize { @subscribers.dup }
        listeners.each { |listener| notify(listener, event) }
        nil
      end

      # Number of attached subscribers (mainly for tests and diagnostics).
      def subscriber_count
        @mutex.synchronize { @subscribers.size }
      end

      # Detach every subscriber (test isolation hook).
      def clear!
        @mutex.synchronize { @subscribers.clear }
        nil
      end

      private

      # Deliver one event to one listener; a raising listener is logged (when
      # logging is configured) and skipped so observability can never break
      # the request it observes.
      def notify(listener, event)
        listener.call(event)
      rescue StandardError => e
        Contractful.log&.<<(
          "contractful: notification subscriber raised #{e.class}: #{e.message}\n"
        )
      end
    end
  end
end
