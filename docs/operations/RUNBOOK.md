# RUNBOOK — symptom → diagnosis → fix

Field guide for failures users and contributors actually hit with
contractful. Format: symptom, diagnosis, fix. Contributions: add entries
for real incidents only, with the Ruby/gem versions where observed.

## TLS / certificate failures

### `OpenSSL::SSL::SSLError: certificate verify failed`

- **Diagnosis:** the host's CA store cannot verify the server chain —
  common with corporate proxies doing TLS interception, minimal Docker
  images, and old CA bundles. Observed concretely in this project's history:
  a 2019-era DigiCert fixture rotted when chains moved to Let's Encrypt/ISRG.
- **Fix:** point the request at a current trust anchor with
  `ssl_ca_file:` (or a `capath` directory), or fix the host store; keep
  `ssl_min_version` explicit. For tests, refresh fixtures to current roots
  (ISRG Root X1 pattern — see `spec/integration/certs/`).
- **Never** "fix" this by disabling verification.

### `Contractful::SSLCertificateNotVerified`

- **Diagnosis:** verification ran and failed explicitly (hostname or chain).
- **Fix:** same as above; if a proxy is intercepting, install the proxy's
  root into the trust you hand to contractful.

## Timeouts

### `Contractful::Exceptions::OpenTimeout` — connecting hangs

- **Diagnosis:** unreachable host, firewall, wrong port, or DNS resolving
  to a black hole.
- **Fix:** verify the URL; raise `open_timeout` only if the target is
  legitimately slow to accept; remember retries will re-hit the same wall —
  `retryable?` is true, so pair `:max_retries` with a sane `open_timeout`.

### `Contractful::Exceptions::ReadTimeout` — response stalls

- **Diagnosis:** server accepted the request but stopped sending (slow
  endpoint, huge report generation).
- **Fix:** raise `read_timeout` for slow endpoints or stream with
  `raw_response`; check server-side. 429/5xx-style stalls are better
  handled by retries (`:max_retries`, `Retry-After` honored).

### `Contractful::Exceptions::WriteTimeout` — upload stalls (2.3+)

- **Diagnosis:** large uploads to slow/constrained links.
- **Fix:** raise `write_timeout`, or chunk/stream the payload.

## Connection behavior

### `Errno::ECONNRESET` / `EPIPE` / `ServerBrokeConnection`

- **Diagnosis:** the peer (or something between) dropped the connection —
  with `persistent: true`, most often a stale pooled keep-alive session the
  server reaped.
- **Fix:** the retry machinery classifies these as retryable; ensure
  `:max_retries` is set for idempotent calls, and make non-GET calls
  `idempotent` (contract flag) so retries carry a stable
  `Idempotency-Key`. The pool invalidates broken connections on checkout.

### Redirect loops (redirect cap exhausted)

- **Diagnosis:** `Location` chain that never settles (bad relative
  redirects, auth loops where each 302 re-asks). Once `:max_redirects`
  (default 10) is exhausted, the library raises the mapped 3xx exception
  (for example `Contractful::Found`) carrying the final redirect response.
- **Fix:** inspect `e.response.history` for the chain; usually an auth
  problem dressed as a redirect problem — check credentials before raising
  `:max_redirects`.

## Auth failures

### 401/403 despite "correct" credentials

- **Diagnosis:** contract auth callables returning `nil` (empty ENV), dual
  header schemes missing one header, netrc entry not matching the host, or
  `auth false` accidentally set on the contract.
- **Fix:** with contract auth, verify resolution order — auth resolves
  before `before_request` callbacks; log (redacted) effective headers in a
  callback during debugging; confirm `ENV` inside the callable, not before
  class definition (callables re-resolve per request, literals freeze at
  declaration).

## Ruby / environment mismatches

### `LoadError: cannot load such file -- base64` (Ruby 4.0)

- **Diagnosis:** something in the bundle still requires the removed
  `base64` default gem.
- **Fix:** upgrade the offending dependency; in *this* codebase the
  equivalent decoding uses `String#unpack1('m')` — do not reintroduce the
  require.

### Spec failures that appear only on one Ruby version

- **Diagnosis:** the known version-behavior seams: URI empty hostname
  (`''` vs `nil` on 3.4+), OpenSSL version symbols (must go through
  `normalize_ssl_version`), rspec-mocks kwargs ambiguity.
- **Fix:** follow TESTING.md's trap list; make specs version-agnostic
  rather than conditional where possible.

### Windows: TLS verification fails out of the box

- **Diagnosis:** the platform gem loads the Windows certificate store via
  ffi; if the gem isn't the platform build, no store is loaded.
- **Fix:** install `contractful` for the `x64-mingw-ucrt` platform (the
  windows gemspec), keep `ffi ~> 1.16`.

## Proxy environments

### Requests fail only inside the corporate network

- **Diagnosis:** proxies. contractful honors `http_proxy`/`https_proxy`/
  `no_proxy` ENV by default.
- **Fix:** set the ENV vars properly, override per request with the
  `:proxy` option, or `proxy: nil` to bypass; TLS-intercepting proxies need
  their root CA trusted (see the SSLError entry).

## When to escalate

If the runbook does not resolve it: open an issue per CONTRIBUTING.md with
`ruby -v`, `Contractful.version`, a redacted reproduction, the full
exception (class + message + `.http_code`), and which of the above entries
you already ruled out. Security-classified surprises (verification
silently skipped, credentials in unexpected places) go to the private
channel, not the tracker — see THREAT_MODEL.md.
