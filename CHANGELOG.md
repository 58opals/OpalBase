# Changelog

All notable public-facing changes to Opal Base are tracked here.

## Unreleased

- No public-facing changes yet.

## v0.4.0 - 2026-07-09

### Added

- Added a curated public `OpalBase.*` facade for Bitcoin Cash wallet, account, address, network, transaction, CashTokens, claimable transfer, CashFusion, AnyHedge, storage, and diagnostics integration surfaces.
- Added BCH claimable transfer primitives, share-code encoding, claimable status resolution, and transaction-building support.
- Added CashTokens and BCMR metadata support, including token metadata repositories, token prefix parsing, token transaction review, token genesis, token mint, token spend, and token commitment mutation helpers.
- Added wallet-backed CashFusion pilot session support, readiness/status facades, participant reservation handling, and macOS-gated OpalFusion integration.
- Added AnyHedge funding preparation surfaces for wallet-backed funding quotes, funding plans, participant material, oracle proof input, and settlement summaries.
- Added descriptor-backed read-only account runtime, wallet trust-domain API lanes, account extended public key helpers, and reusable payment address scaffolding.
- Added Secure Enclave-backed mnemonic persistence helpers, wallet snapshot persistence separation, redacted diagnostics mappings, and package-level diagnostics facade adoption through `OpalDiagnostics`.
- Added a BCH builder starter guide covering installation, wallet creation and restore, CashAddr receive-address reservation, Fulcrum-backed refresh, BCH spend preparation for external review, secret/signing boundaries, CashTokens, CashFusion, AnyHedge, diagnostics, and public API test pointers.
- Added a recipe cookbook for common builder tasks: create/restore wallet, snapshot persistence, public descriptors, receive BCH, Fulcrum sync, confirmation refresh, external-review spends, in-process spend/broadcast, CashTokens metadata, CashFusion, AnyHedge funding, diagnostics, and validation commands.
- Added a trust-boundary guide covering secret-bearing authority, descriptor-backed sync, receive-address reservation, `privateAccount` authoring, external signing review, broadcast separation, Secure Enclave limits, and redacted diagnostics.
- Added a public-safe release-readiness page for builder review versus SemVer release expectations.

### Changed

- Moved raw cryptography and Fulcrum transport responsibilities into sibling packages, using `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, `OpalHedge`, and `OpalDiagnostics` as public package dependencies.
- Restructured the README as the public front door with package role, install paths, trust-boundary summary, 5-minute quick start, docs map, validation commands, release status, and the `0.4.0` install snippet.
- Revised the public API guide into a facade reference organized around the public `OpalBase.*` integration layer.
- Revised the architecture guide into a concise package-boundary and integration-lane map.
- Normalized public source naming around `OpalBase+...` declarations and split local/network Swift Testing targets for deterministic local validation versus opt-in live Fulcrum smoke validation.
- Updated dependency revisions and tracked `Package.resolved` for public `develop` branch dependencies.

### Fixed

- Hardened wallet snapshot restoration, wallet/account state updates, spend finalization, CashFusion failure release paths, token validation, malformed input parsing, transaction hash validation, output ordering, CompactSize bounds, reader byte counts, diagnostics redaction, and Fulcrum network configuration behavior.

### Release Notes

- Public-facing docs and release notes should call out the license posture change from the older README's MIT claim to Apache License 2.0, matching the repository `LICENSE` file.
- The `v0.4.0` release candidate uses public sibling package URLs and tracked `Package.resolved` revisions while the manifest continues to depend on sibling public `develop` branches. Moving those dependencies to public SemVer tags remains a separate maintainer-approved dependency change.
