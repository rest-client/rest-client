# ADR 0004 — Resolving the skills-review observations

- **Status:** Accepted (2026-10, shipped via the review-observations PR)
- **Context:** the repository review (following the ruby-agent-skills
  patterns) documented four inherited quirks that were deliberately left
  untouched at review time. Each is now either fixed or consciously
  finalized as a design decision instead of remaining an accident.

## Observations and decisions

### 1. `Payload::Base#to_s` called `@stream.seek(0)` unguarded — **fixed**

`to_s` read the whole stream and then rewound it so the payload stayed
readable. For streamed payloads (`Payload::Streamed` wraps any object that
responds to `#read`), the rewind raised `NoMethodError` (plain reader
objects without `#seek`) or `Errno::ESPIPE` / `IOError` (pipes, sockets,
closed streams). Because `Request#log_request` inspects small payloads via
`short_inspect` → `to_s`, even just enabling Contractful logging could crash
a request whose body was a non-seekable stream.

Decision: rewind via a best-effort `rewind_stream` helper — guard with
`respond_to?(:seek)` and rescue `IOError`/`SystemCallError`, mirroring the
already-defensive `Payload::Base#rewind`. Non-rewindable streams are left
positioned at EOF instead of raising. The request body itself is
transmitted through `#read` (Net::HTTP consumes the payload object), so
this only ever affected the logging path.

### 2. `stringify_headers` passes String keys through verbatim — **kept, harm fixed**

Only Symbol keys (`:content_type`) are normalized to `Content-Type`
capitalization; String keys (`'content-type'`) go to the wire exactly as
spelled. This matches rest-client 1.x/2.x (upstream issue #599), and we
keep it: canonicalizing String keys would silently change the spelling of
headers on the wire for existing users — which breaks, among other things,
signature schemes that canonicalize over sent header names.

The real harm was never the passthrough itself: header names that differed
only in case were treated as different headers. A user-supplied
`'content-type'` therefore coexisted with the default `'Accept'`-style
headers instead of overriding them, duplicate headers reached the wire,
and the accidental-override warnings (which compare keys exactly) did not
fire.

Decision: `make_headers` now merges header sets case-insensitively
(`merge_headers` / `header_key_for`). A later header whose name matches an
earlier one case-insensitively replaces it, keeping the later casing. The
payload-override and Cookie-override warnings use the same case-insensitive
lookup. Net effect: the wire passthrough is unchanged for non-colliding
names, and collisions now behave the way the code always claimed they
did.

### 3. Connection pool has no checkout cap — **kept, design finalized**

`ConnectionPool` retains at most `max_idle` idle connections per key but
never limits simultaneous checkouts: when no idle connection is available,
`checkout` builds a new one. A hard cap would force a choice between two
new failure modes — blocking until another request returns its connection
(deadlock risk: a borrower must first make progress on a request that
needs a connection) or raising (breaking requests that used to succeed) —
in exchange for bounding exactly the resource that the non-persistent
path also leaves unbounded (concurrent requests each open their own
connection).

Decision: keep the open-when-exhausted behavior. Bound what a pool safely
can (idle retention via `max_idle`), account for what is out (via
`stats`), and leave concurrency control to the caller, where backpressure
belongs. The class documentation states this explicitly.

### 4. `Response < String` and the response-block arity — **kept, API finalized**

`Response` subclasses `String` (the body) while carrying response metadata,
and a user response block is called as `block.call(response, self, res,
&block)` — response, request, raw Net::HTTP result, original block. This
is public API since rest-client 1.x: consumers index into responses as
strings, and 3-arity (plus the block passthrough) response blocks are
widespread.

Decision: keep both. A `Response` that is not a `String`, or a block
invocation convention that changed, would be a new major version, not a
review fix. Any future replacement should ship behind a deprecation window
and a parallel accessor API rather than an in-place change.

## Consequences

- `log_request` is safe with non-seekable streamed payloads; regression
  specs cover plain readers, pipes, and the `short_inspect` path.
- Case-variant header collisions collapse to one header instead of
  duplicating on the wire, and the warnings fire; verbatim String-key
  passthrough is pinned by specs as the compatibility contract.
- The pool's contract is intentional and documented rather than implicit;
  `max_idle` remains the only tunable that can silently close connections.
- `Response < String` and the block arity are frozen API; changes require
  a major-version plan.
