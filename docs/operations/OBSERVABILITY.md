# OBSERVABILITY — proving the library (and its callers) are healthy

contractful is a library: it does not run a process, hold metrics or ship
dashboards. Observability here has two layers — what the gem exposes for
**host applications** to observe with, and what the **project itself** uses
to prove its own health (CI, specs, packaging). There is deliberately no
telemetry (INTEGRATIONS.md policy): the gem reports only to whoever asks.

## What the gem exposes to host applications

### Logging

- `Contractful.log = logger` sets a process-wide logger; the `CONTRACTFUL_LOG`
  environment variable initializes it (values like `stdout`/`stderr`).
  Per-request override via the `:log` option.
- Logged content: the request line (method, URL, payload summary) and the
  response line (status, content type, size) — enough to correlate with
  application logs, not a full wire dump.
- **Redaction guidance (security-relevant):** request lines include URLs.
  URL userinfo is supported: the password is redacted from request logs,
  notifications and `Request#inspect` (the username remains). Prefer auth
  headers or `user:`/`password:` options, because proxies and custom handlers
  can still see the raw URL. Auth headers are not logged, but callers who add
  custom logging via `before_request` must redact `Authorization`, `Cookie`,
  and API-key headers themselves. Assume anything you put in a header may end
  up in *your* logs if you log the context.

### Exceptions as diagnostics

Every failure is a precise exception carrying evidence (see
ERROR_HANDLING.md): `.response`/`.http_code`/`.http_body` on response
errors, `.original_exception` on wrapped network errors, contract errors
naming param/contract/expectation/value. Applications get structured
diagnostic context by rescuing the documented roots — no string parsing.

### Event notifications

`Contractful::Notifications` is the machine-readable observability surface:
every request posts `request`, `response` and (when applicable) `retry`
events with method, url, attempt, status, duration_ms and the retry cause.
Subscribers are isolated — a raising subscriber is logged and skipped —
and the optional `contractful/notifications/active_support` bridge
re-posts everything to ActiveSupport::Notifications as
`contractful.<name>` for Rails/APM consumption. Prefer events over log
scraping for metrics; the log remains the human-readable mirror.

### Runtime quota visibility

`response.rate_limit` (parsed `RateLimit-*`/`X-RateLimit-*` headers) and
`response.rate_limited?` let hosts observe quota burn and make pacing
decisions; `nil` means the server publishes nothing (data absence, not an
error).

### Introspection as static observability

For contract clients, `ClientClass.contracts`, `contract_for(:name).describe`
and the instance reflection API give a truthful, generated-from-source
inventory of what the client does — the substrate for building dashboards,
docs or MCP tool listings without scraping code.

### Middleware points

`before_request` (mutable request context) is the supported place for
hosts to add tracing headers, request IDs and timing capture;
`after_response` observes validated responses for metrics. Anything more
invasive (transport swapping) is deliberately not offered (ARCHITECTURE.md).

## What proves the project itself is healthy

| Signal | Where | Healthy looks like |
| --- | --- | --- |
| CI matrix | GitHub Actions, `.github/workflows/ci.yml` | unit + integration green on 3.0–4.0 on every push |
| `ruby-head` job | same workflow | non-blocking; red means "investigate soon", not "halt" |
| Spec counts | run output | honestly reported (`N examples, 0 failures`); trends watched across releases |
| Live TLS specs | integration suite vs httpbin.org | green — catches certificate-chain rot before users do |
| Gem builds | release checklist | both gemspecs build; metadata URIs resolve |
| Released metadata | rubygems.org | changelog URI, source URI, MFA flag present |

## Debugging workflow (for contributors)

1. Reproduce with a spec or a snippet using the local library
   (`ruby -Ilib`).
2. Enable logging: `CONTRACTFUL_LOG=stdout` or `Contractful.log =
   Logger.new($stdout)` — read the request/response lines, not guesses.
3. Inspect the exception: class, `.response`, `.original_exception`.
4. Contract clients: `client.contract_for(:name).describe` to confirm what
   the library thinks the operation is.
5. If behavior differs between Rubies, run the matrix locally via mise —
   version-dependent behavior (URI, OpenSSL, rspec kwargs) is the top
   source of "works on my machine".

## Non-goals

No built-in metrics, tracing export, or pluggable telemetry backends; the
callback surface is the integration point for hosts that want those. The
library stays silent by default and honest when asked.
