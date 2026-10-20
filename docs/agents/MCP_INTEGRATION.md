# MCP integration — Model Context Protocol (conditional document)

**Status: not currently used in this repository.** contractful is an HTTP
client library; it neither ships an MCP server nor consumes MCP tools in its
build, test or release workflow. This document exists so that the day MCP
becomes relevant, the ground rules are already written. Do not extend it with
speculative architecture — record actual decisions in `docs/adr/` when they
are made.

## When this document becomes relevant

Two scenarios would activate it:

1. **An MCP server built on contractful.** The contract-first layer maps
   naturally onto MCP tool schemas: every `Contractful::Contract::Definition`
   already exposes `#name`, `#params`, `#describe` and the introspection API
   (`contracts`, `contract_for`), which is exactly the metadata an MCP
   `tools/list` handler needs. A server could generate tool descriptions from
   contract introspection instead of maintaining a parallel tool registry —
   keeping one source of truth.
2. **Agents operating on this repository gain MCP tool access** (browser
   tools, issue trackers, package registries). In that case the tool policy
   below applies on top of
   [AGENT_TOOL_POLICY.md](../security/AGENT_TOOL_POLICY.md).

## Ground rules when MCP is introduced

- **Least privilege.** Each MCP server gets an explicit allowlist of the
  tools it may call and the repositories/hosts it may reach. No blanket
  "everything" grants.
- **No secrets across the boundary.** GitHub tokens, RubyGems credentials and
  API keys are never passed through an MCP server. Credentials stay in the
  operator's environment; the server receives scoped, revocable access or
  nothing.
- **Untrusted content discipline.** Everything an MCP server returns — issue
  bodies, web pages, file listings — is untrusted input, a potential prompt
  injection vector. When such content drives code changes, it flows through
  the same closed-request validation rules as any other input: explicit
  declarations, strict checks, exceptions on violation.
- **Audit trail.** Agent actions authorized through MCP must still land as
  reviewable commits and PRs. MCP never becomes a side channel that mutates
  the repository outside git history.
- **Separation of concerns.** Any MCP server code lives in its own repository
  or gem, not inside contractful. This repository's runtime dependency set is
  deliberately small and must not grow to host agent infrastructure.

## For consumers building MCP tools on contractful

If you expose an HTTP API to AI agents via an MCP server and use contractful
under the hood, the contract layer gives you the right building blocks:
declare one contract per tool, use the typed params as the tool's input
schema (strict mode gives you closed-schema rejection of malformed tool
calls), and let `UnexpectedResponse` surface malformed backend answers as
tool errors rather than silent garbage. See [API.md](../engineering/API.md)
for the introspection surface.
