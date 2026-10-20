# Agent tool policy — what AI agents may and may not do here

This policy defines the permission boundaries for AI coding agents operating
on the contractful repository, complementing [AGENTS.md](../../AGENTS.md)
(how to work) and [AGENT_WORKFLOWS.md](../agents/AGENT_WORKFLOWS.md) (the
workflow). It exists because agents have shell, file and network access, and
that access must be bounded by explicit rules rather than vibes. Where an
action is neither clearly allowed nor clearly forbidden, the agent must ask
the operator first.

## Allowed without approval

- Read any file in the repository, run read-only git commands
  (`status`, `log`, `diff`, `fetch`).
- Modify and create repository files, including specs and documentation.
- Run the test suite, rake tasks, `gem build` for both gemspecs, and ad-hoc
  Ruby snippets that exercise the library.
- Commit to feature branches with descriptive, conventional messages.
- Push feature branches and update PR descriptions **when the operator has
  configured working credentials for this session**.
- Install the project's own development dependencies via `bundle install`.

## Requires explicit operator approval

- `gem push` to RubyGems and anything release-shaped (version bumps on
  release commits are normal work; publishing is not).
- Creating or deleting git tags.
- Adding, removing or upgrading dependencies beyond what `bundle install`
  resolves from the committed gemspec (a new *runtime* dependency additionally
  requires an ADR).
- Breaking changes to the public API (anything documented in
  [API.md](../engineering/API.md)).
- Editing `.github/workflows/ci.yml` in ways that alter permissions,
  authentication or the test matrix's meaning.
- Force-pushing, rewriting history, deleting branches, or operating on
  `master` directly for anything larger than a small, green, reviewable
  commit.
- Any network call from scripts beyond the offline test suite and
  github.com/git operations (for example hitting httpbin.org manually is
  fine; making it part of the test flow is not).

## Forbidden

- Committing secrets, tokens, passwords or credential files — including
  "temporary" ones.
- Leaving an authenticated remote URL configured after a push; remotes must
  be tokenless at the end of every session.
- Disabling, skipping, stubbing-out or weakening tests to make a red suite
  green (including `WebMock.disable!` outside the explicit live-spec files
  that already use it).
- Silently editing CI to route credentials anywhere, or adding network
  exfiltration of any kind.
- Echoing token contents into logs, commit messages, fixtures or docs.
- Operating on files outside the repository checkout and the operator's
  designated workspace directories.

## Secret handling

Credentials arrive from the operator (in the reference environment, as a
token file *outside* the repository). Rules:

1. Read the token into the shell session only when needed; never write it to
   a file inside the repo, and never `echo` it.
2. Prefer a git credential helper over token-in-URL so tokens never appear in
   command output; if token-in-URL is unavoidable, reset the remote to its
   tokenless form immediately after the push.
3. Treat any accidental disclosure as an incident: stop, report to the
   operator, assume the credential is compromised and needs rotation.

## Audit trail

Git history is the primary audit record — every change an agent makes must
be a reviewable commit. Session-level context (what was attempted, what was
decided, what remains) belongs in the operator's work log, which lives
outside the repository. PRs aggregate commits into reviewable units and are
the approval boundary for anything that reaches `master`.

## Incident rule

If an agent detects a policy violation after the fact (a committed secret, a
skipped test, an unauthorized push): stop work, disclose it to the operator
immediately with full context, and do not attempt to quietly fix or hide it.
Secrets that reached GitHub are compromised regardless of deletion — the
operator decides on rotation and, if necessary, history remediation.
