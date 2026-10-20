# Feature specification template

Copy this file to `docs/implementation/features/<feature-id>.md` for any
feature large enough to need more than a commit message — anything that
changes the public API, adds a contract DSL declaration family, or touches
error semantics. Small fixes do not need a feature file; they need specs and
a good commit message. Requirements live in
[docs/requirements/REQUIREMENTS.md](../requirements/REQUIREMENTS.md); the
feature file links to its requirement rows.

---

## Feature: `<name>` (REQ-XXX)

**Status:** draft | in-progress | implemented | abandoned
**Branch/PR:** `<branch>` / `<link>`
**Introduces behavior in version:** `<X.Y>`

### Summary

One paragraph: what this feature makes possible, stated in user terms. If a
reader stops here, they should know whether this feature concerns them.

### Motivation

Why now: the problem observed, the requests or failures that motivate it,
and what people do today as a workaround. A feature without a concrete
motivation is a hypothesis, and hypotheses belong in an issue, not a
feature spec.

### Public API sketch

The declaration or calls users will write, before any implementation. For
contract-layer features this sketch is the specification — review it as
carefully as code.

```ruby
# what the user writes
contract :create_order, 'POST /orders' do
  # ...
end

# what they get back / what raises
```

### Semantics and rules

- Closed/open classification: what is validated pre-flight, what is
  additive data
- Error behavior: which exceptions, raised when, carrying what
- Inheritance/override behavior for new settings
- Interaction with existing features (retries, pooling, callbacks, auth)

### Acceptance criteria

Given/when/then statements, each mapping to at least one spec:

1. Given a contract declared with `<X>`, when called with `<Y>`, then `<Z>`
   raises/returns `<W>` before/without any network traffic.
2. ...

### Test plan

- Unit specs (which files, roughly how many examples)
- Integration coverage (offline WebMock; live httpbin only if the feature
  needs real TLS/headers)
- Negative cases: the violation paths, not just the happy path

### Docs to update

- README section (runnable example)
- API.md rows (options, methods, exceptions)
- history.md entry text
- REQUIREMENTS.md status flip

### Risks and mitigations

What could break (compatibility, thread safety, generated-name collisions)
and how the design bounds it. Reference or create an ADR if the feature
changes architecture.

### Work breakdown

Ordered one-commit tasks, per the repository cadence:

1. `<task>` — specs + code
2. `<task>` — docs + history
3. ...

---

## Filled example (abridged)

```markdown
## Feature: response_rate_limit (REQ-F10)

Summary: every response exposes parsed quota state so callers can pace
themselves without parsing headers.

Motivation: trading APIs return 429s with retry information spread across
IETF and legacy headers; every consumer re-implements the parsing badly.

Public API sketch:
  response.rate_limit&.remaining   # => 98
  response.rate_limited?           # => true on 429/exhausted quota

Acceptance:
1. Given a response with RateLimit-* headers, when rate_limit is called,
   then remaining/reset_in parse correctly (IETF preferred over legacy).
2. Given no rate-limit headers, rate_limit returns nil — data absence is
   not an error.
```
