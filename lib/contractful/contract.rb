# frozen_string_literal: true

require 'securerandom'

module Contractful
  # Contract-first architecture for contractful.
  #
  # Instead of hand-writing request code, you declare a *contract* — the HTTP
  # shape of an API (verb, path, typed parameters, expected responses) — and
  # metaprogramming generates the client methods, path builders, validation
  # and introspection for you:
  #
  #   class GitHubAPI
  #     include Contractful::Contract
  #
  #     base 'https://api.github.com'
  #     default_headers 'Accept' => 'application/vnd.github+json'
  #
  #     contract :list_users, 'GET /users' do
  #       param :page,     Integer, default: 1
  #       param :per_page, Integer, inclusion: (1..100), default: 30
  #     end
  #
  #     contract :create_issue, 'POST /repos/:owner/:repo/issues' do
  #       param :owner, String, required: true
  #       param :repo,  String, required: true
  #       param :title, String, required: true
  #     end
  #   end
  #
  #   api = GitHubAPI.new
  #   api.list_users(page: 2)
  #   api.create_issue(owner: 'octo', repo: 'hello', title: 'Hi')
  #
  # The contract *is* the implementation: nothing about the request is
  # written imperatively. Violations raise precise errors from the
  # {Contract::Error} hierarchy instead of producing malformed requests.
  module Contract
    # Root of all contract errors (definition mistakes, param violations,
    # response mismatches, misconfiguration).
    class Error < StandardError; end

    # Raised at definition time when a contract, param or macro is invalid.
    class InvalidDefinition < Error; end

    # Raised at execution time when no base URL is configured.
    class MissingBaseUrl < Error; end

    # Base class for parameter violations (missing, unknown, invalid).
    class ParamError < Error; end

    # A required param was not provided.
    class MissingParam < ParamError; end

    # A param was provided that the contract does not declare (strict mode).
    class UnknownParam < ParamError; end

    # A param value could not be coerced/validated against its declared type.
    class InvalidParam < ParamError; end

    # The HTTP response did not satisfy the contract's response declaration
    # (unexpected status code, body type mismatch or failed verify_response
    # block). The offending +response+ is attached for inspection.
    class UnexpectedResponse < Error
      attr_reader :response

      def initialize(message = nil, response: nil)
        @response = response
        super(message)
      end
    end

    # Sentinel for "no default value declared" (distinct from `default: nil`).
    NO_DEFAULT = Object.new.freeze
  end
end

require_relative 'contract/param'
require_relative 'contract/response_field'
require_relative 'contract/auth'
require_relative 'contract/pagination'
require_relative 'contract/definition'
require_relative 'contract/config'
require_relative 'contract/executor'
require_relative 'contract/dsl'
