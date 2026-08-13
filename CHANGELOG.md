# Changelog

All notable public-facing changes to Opal Base are tracked here.

## Unreleased

### Added

- Added the Opal-owned Cash Code v1 candidate implementation: strict `cashcode:`/`cashcodetest:` codec, sender and receiver derivation, exact transaction matching, transport-neutral and Fulcrum candidate readers, deterministic public conformance vectors, bounded confirmed restoration, deterministic mempool replacement, trusted reorganization rollback and replay, generation-staged public-only state, authorized receiving-capability rederivation, exact UTXO confirmation, opaque-key spend plans, account-backed sender preparation, and cancellable bounded Schnorr prefix grinding.

### Changed

- Made secret-persistence policy construction-bound for the next explicitly breaking pre-1.0 release. `Storage`, `Security`, custom `StoredMnemonicPersistence`, persistence sessions, and the secret interactor now require or inherit one explicit root policy instead of defaulting or accepting per-save fallback overrides; migration guidance is in the public API guide.
- Made Cash Code spend-plan build and reservation disposition single-use across every plan copy and exposed catchable lifecycle errors, including terminal uncertain disposition failure.
- Added a public [Cash Code v1 readiness](docs/cash-code-readiness.md) source of truth that separates implementation completeness, production readiness, stable release availability, and ecosystem standardization.
- Moved `OpalDiagnostics` to its public `0.2.0` SemVer requirement and refreshed the tracked public `develop` revisions for `SwiftFulcrum`, `OpalCrypto`, and `OpalFusion`.
- Replaced the experimental reusable-payment-address closure scaffold with
  profile-aware value APIs; legacy Electron Cash `paycode:` values are now
  strict read-only migration data and cannot be generated, sent to, or matched
  as Cash Code v1.
- Bound Cash Code restoration state to the exact profile, network, public keys, non-secret key origin, restore start, cursor, matched outputs, derivation contexts, revisions, and bounded reorganization history while excluding signing capabilities, complete Cash Codes/paycodes, filter prefixes, shared material, and raw transactions.
- Updated decoding limits, diagnostics privacy, mnemonic validation errors, and Fulcrum configuration error translation for the newer dependency APIs.
- Changed non-fungible token additions and removals in `Transaction.History.Record.TokenDelta` from sets to ordered arrays so repeated equivalent CashTokens are preserved.

### Removed

- Temporarily removed the source-breaking experimental `OpalBase.Hedge` public API and its `OpalHedge` dependency while OpalHedge is not ready for adoption. Reintroducing AnyHedge will use a newly reviewed API.

### Fixed

- Bounded branch-and-bound coin selection and added a deterministic fallback so adversarial UTXO sets cannot trigger exponential recursion.
- Rejected snapshots with excessive implicit address spans and made address inventory restoration atomic on derivation failure.
- Preserved duplicate non-fungible token occurrences when computing, netting, persisting, and restoring transaction history.
- Serialized in-process wallet persistence transactions and public storage facades, restored the previous generation marker after partial commit failures, and retained staged artifacts when rollback could not be confirmed.
- Rejected private and reserved BCMR IP literals and local-use hostnames—including redirect targets—before issuing network requests, and documented that callers need a trusted transport for untrusted DNS names.

## v0.4.1 - 2026-07-11

### Changed

- Updated the tracked public `develop` revisions for `OpalCrypto`, `OpalFusion`, and `OpalHedge`; `SwiftFulcrum` and `OpalDiagnostics` were already current.

### Fixed

- Hardened Fulcrum configuration and reconnect behavior by clamping invalid timeout, retry, delay, jitter, and message-size values.
- Canonicalized transaction and block hash handling, validated returned broadcast identifiers, and rejected malformed or prefixed transaction hexadecimal input.
- Tightened Bitcoin Cash balance bounds, standard locking-script serialization, transaction decoding, token metadata URL handling, and path traversal validation.
- Improved wallet snapshot persistence cleanup, stale reservation validation, unconfirmed transaction handling, and failure-path consistency.

### Release Notes

- This patch release applies stricter normalization and rejection of invalid network, hash, locking-script, token metadata, and persistence inputs. Apps that passed malformed values may now receive validation errors or clamped configuration values.
- The `v0.4.1` release uses public sibling package URLs and tracked `Package.resolved` revisions while the manifest continues to depend on sibling public `develop` branches.

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
