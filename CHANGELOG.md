# Changelog

All notable public-facing changes to Opal Base are tracked here.

## Unreleased

### Added

- Added a BCH builder starter guide covering installation, wallet creation and restore, CashAddr receive-address reservation, Fulcrum-backed refresh, BCH spend preparation for external review, secret/signing boundaries, CashTokens, CashFusion, AnyHedge, diagnostics, and public API test pointers.
- Added a recipe cookbook for common builder tasks: create/restore wallet, snapshot persistence, public descriptors, receive BCH, Fulcrum sync, confirmation refresh, external-review spends, in-process spend/broadcast, CashTokens metadata, CashFusion, AnyHedge funding, diagnostics, and validation commands.
- Added a trust-boundary guide covering secret-bearing authority, descriptor-backed sync, receive-address reservation, `privateAccount` authoring, external signing review, broadcast separation, Secure Enclave limits, and redacted diagnostics.
- Added a public-safe release-readiness page for builder review versus SemVer release expectations.

### Changed

- Restructured the README as the public front door with package role, install paths, trust-boundary summary, 5-minute quick start, docs map, validation commands, and release status.
- Revised the public API guide into a facade reference organized around the public `OpalBase.*` integration layer.
- Revised the architecture guide into a concise package-boundary and integration-lane map.
- Clarified that a future `v0.4.0` release needs coordinated dependency hardening and release-readiness validation before it is presented as a SemVer release.

### Release Notes Required

- The next public release notes must call out the license posture change from the older README's MIT claim to Apache License 2.0, matching the repository `LICENSE` file.
- Before a `v0.4.0` release, decide whether sibling dependencies should move from public `develop` branches to public SemVer tags. Exact public revisions can support review candidates, but coordinated sibling tags are the preferred release state.
