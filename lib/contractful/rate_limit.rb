# frozen_string_literal: true

require 'time'

module Contractful
  # Parsed rate-limit information from a response's headers.
  #
  # Understands both the IETF ratelimit headers (RateLimit-Limit /
  # RateLimit-Remaining / RateLimit-Reset / RateLimit-Policy) and the legacy
  # X-RateLimit-* convention, preferring the IETF spelling when both are
  # present.
  #
  #   info = response.rate_limit
  #   info.limit      # => 5000
  #   info.remaining  # => 4998
  #   info.reset      # => Time (or nil when the server does not say)
  #   info.policy     # => "10;w=1" (or nil)
  #   info.exhausted? # => true when remaining is reported as 0
  #   info.reset_in   # => seconds until the quota resets (or nil)
  #
  # APIs may document their rate limits in prose without ever sending the
  # headers (DhanHQ, for example) — #rate_limit then returns nil, which is
  # data absence, not an error.
  class RateLimit
    # Leading-integer extraction handles both plain integers ("5000") and
    # the IETF "limit, limit;w=window" description form.
    LEADING_INTEGER = /\A\s*(\d+)/

    attr_reader :limit, :remaining, :reset, :policy

    # The raw parsed header values, for diagnostics.
    attr_reader :raw

    def initialize(limit: nil, remaining: nil, reset: nil, policy: nil, raw: {})
      @limit = limit
      @remaining = remaining
      @reset = reset
      @policy = policy
      @raw = raw.freeze
    end

    # Build a RateLimit from a beautified headers hash (lowercase underscore
    # symbols, as produced by AbstractResponse#headers). Returns nil when no
    # rate-limit headers are present at all.
    def self.from_headers(headers)
      return nil unless headers.is_a?(Hash)

      parsed = {}
      parsed[:limit] = parse_limit(pick(headers, :ratelimit_limit, :x_ratelimit_limit))
      parsed[:remaining] = parse_integer(pick(headers, :ratelimit_remaining, :x_ratelimit_remaining))
      parsed[:reset] = parse_reset(pick(headers, :ratelimit_reset),
                                   pick(headers, :x_ratelimit_reset))
      parsed[:policy] = pick(headers, :ratelimit_policy)

      raw = {}
      headers.each do |key, value|
        raw[key] = value if key.to_s.start_with?('ratelimit_', 'x_ratelimit_')
      end
      parsed[:raw] = raw

      return nil unless parsed[:limit] || parsed[:remaining] || parsed[:reset] || parsed[:policy]

      new(**parsed)
    end

    # True when the server reports the quota as used up.
    def exhausted?
      remaining == 0
    end

    # Seconds until the quota resets (never negative), or nil when unknown.
    def reset_in
      return nil unless reset

      secs = reset - Time.now
      secs.positive? ? secs : 0.0
    end

    def to_s
      parts = []
      parts << "#{remaining}/#{limit}" if limit || remaining
      parts << "resets in #{reset_in&.round(3)}s" if reset
      parts << "policy #{policy}" if policy
      parts.empty? ? 'RateLimit (no data)' : "RateLimit #{parts.join(', ')}"
    end

    def inspect
      "#<Contractful::RateLimit limit=#{limit.inspect} remaining=#{remaining.inspect} " \
        "reset=#{reset.inspect} policy=#{policy.inspect}>"
    end

    # Pick the first present value among candidate header keys (keys are
    # beautified symbols; values may be single strings or arrays).
    def self.pick(headers, *names)
      names.each do |name|
        value = headers[name]
        value = value.first if value.is_a?(Array)
        value = value.to_s.strip
        return value unless value.empty?
      end
      nil
    end

    def self.parse_limit(value)
      return nil unless value

      match = value.match(LEADING_INTEGER)
      match && match[1].to_i
    end

    def self.parse_integer(value)
      parse_limit(value)
    end

    # IETF reset is a duration in seconds or an HTTP-date; the legacy
    # X-RateLimit-Reset is an epoch timestamp.
    def self.parse_reset(ietf_value, legacy_value)
      if ietf_value
        if ietf_value.match?(/\A\d+\z/)
          Time.now + ietf_value.to_f
        else
          begin
            Time.httpdate(ietf_value)
          rescue StandardError
            nil
          end
        end
      elsif legacy_value&.match?(/\A\d+\z/)
        Time.at(legacy_value.to_i)
      end
    end
  end
end
