# Cash Code v1 Readiness

This page is the source of truth for the current implementation and release readiness of Cash Code v1 in Opal Base. The wire profile remains defined by the [Cash Code v1 Candidate Profile](cash-code-v1.md).

## Current Status

| Dimension | Public status |
| --- | --- |
| Profile | Cash Code v1 is an Opal-owned candidate profile, not a Bitcoin Cash ecosystem standard. |
| Implementation | The unreleased source contains the intended sender, receiver, restoration, persistence, mempool, reorganization, and received-output spending paths. |
| Production readiness | The reference implementation is not yet production-ready; the feature and release gates below remain open. |
| Stable availability | Cash Code v1 is tracked under `Unreleased` and is not included in the stable `v0.4.1` release. |
| Ecosystem boundary | Another implementation is required for broader interoperability or standardization claims, not for continued Opal production hardening or adoption. |

## Implemented Reference Path

- Strict `cashcode:` and `cashcodetest:` encoding and decoding bind the profile, network, fixed 16-bit filter prefix, compressed public keys, child index zero, and zero expiration.
- Legacy Electron Cash `paycode:` and `paycodetest:` values remain strict read-only migration data and cannot be generated, sent to, or matched as Cash Code v1.
- Sender preparation derives the exact payment from a qualifying compressed-P2PKH input, preserves BCH and complete CashToken data, fee-corrects the transaction, and performs bounded cancellable Schnorr prefix grinding. Every plan copy retains one actor-owned lifecycle, so one valid build and one terminal reservation disposition are the maximum.
- Receiver matching independently validates raw transaction hashes, derives exact compressed-P2PKH locking bytecode, retains matching transaction outputs, and rederives opaque spending capabilities only after authorized key access.
- Durable restoration uses bounded confirmed windows, atomic cursor advancement, deterministic mempool snapshot replacement, trusted reorganization rollback and replay, revision checks, and generation-staged public-only state.
- Public deterministic positive and negative vectors cover identifiers, derivation intermediates, matching, sender construction, and strict rejection cases.

## Cash Code Feature Readiness

| Area | Current evidence | Remaining production gate |
| --- | --- | --- |
| Profile and conformance | The strict codec, derivation, and matching behavior are implemented, and public positive and negative vectors provide deterministic conformance material. | No external implementation is required for Opal readiness. Another implementation is required only before making broader interoperability or standardization claims. |
| Receiver restoration | Deterministic tests cover bounded confirmed windows, cancellation, restart, mempool replacement, reorganization replay, persistence failures, exact transaction hashes, UTXO confirmation, and CashToken preservation. | Exercise the real Fulcrum RPA reader, raw-transaction reader, restoration actor, and production storage path against a controlled RPA-capable Fulcrum lifecycle. |
| Historical performance | The production-shaped restoration path exists, while local test doubles intentionally avoid making performance claims. | Run the representative release benchmark defined by the [RPA Historical Scan Benchmark Gate](rpa-historical-scan-benchmark-gate.md), including incremental, maximum-window, restart, mempool, and reorganization workloads. |
| Sender grinding | Bounded random-nonce signing, cancellation, prefix validation, mutation rejection, BCH payments, CashToken payments, and the first-30-input rule are implemented. | Demonstrate a successful grind through the real random-nonce path, verify the resulting transaction with a Bitcoin Cash virtual machine, and measure representative Apple-device performance before selecting any hot-path optimization. |
| Sender lifecycle | One actor shared by every plan copy admits one build, automatically cancels after build failure or task cancellation, admits exactly one completion-or-cancellation disposition after success, and terminalizes uncertain disposition failures without retry. The fixture-light `CashCodeSpendPlanLifecycleValidator` covers this without random-nonce signing. | No separate implementation gate remains. Re-run the focused lifecycle suite in release validation and keep application broadcast acceptance separate from reservation completion. |

## Opal Base Release Readiness

| Area | Current status | Remaining release gate |
| --- | --- | --- |
| Clean validation | Cash Code has deterministic local test coverage and Opal Base documents its Xcode and Metal Toolchain requirements. | Pass a clean-checkout release build and the full test suite under the supported toolchain after all Cash Code feature gates are closed. |
| Automation | The repository does not currently contain repository-owned continuous integration configuration. | Add public continuous integration that enforces the clean build, full tests, and public-boundary checks required for release. |
| Dependency requirements | Public sibling package URLs and resolved revisions are tracked, while `SwiftFulcrum`, `OpalCrypto`, and `OpalFusion` remain branch-based requirements. | Replace mutable sibling `develop` requirements with approved immutable tags or SemVer requirements before treating the Cash Code release as reproducible for package consumers. |
| Stable publication | Cash Code v1 remains under `Unreleased`. | Publish it only through a validated SemVer release after the feature, validation, automation, and dependency gates are closed. |

These Cash Code release gates are intentionally stricter than the branch-based dependency posture accepted for the `v0.4.1` developer-preview release line.

## Wallet Integration Boundaries

Opal Base owns the Cash Code profile, derivation, matching, restoration state contract, persistence boundary, sender preparation, single-use plan lifecycle, and received-output spending primitives. Integrating wallet and application code still owns secret storage and authorization, exact key-origin recovery metadata, stable registration identity, scheduling, trusted chain-event detection, consent, migration UX, broadcast policy, the decision to complete or cancel a successfully built plan, and application lifecycle.

These responsibilities are integration boundaries rather than missing Cash Code wire-profile features. The profile does not assign a portable mnemonic derivation path, and seed-only recovery must not be advertised as portable.

## Public Claims Boundary

- Public documentation may call Cash Code v1 an Opal-owned candidate profile and the current code an unreleased reference implementation.
- Public documentation must not call Cash Code v1 a Bitcoin Cash ecosystem standard, a production-ready implementation, or a stable Opal Base feature while the corresponding gates remain open.
- Opal implementation, testing, hardening, and adoption do not require community consensus or a second implementation.
- Broader interoperability or standardization claims require another implementation to consume the public vectors and reproduce the same bytes and behavior.

## Evidence

- [Cash Code v1 Candidate Profile](cash-code-v1.md)
- [Cash Code v1 Conformance Vectors](cash-code-v1-vectors.json)
- [Cash Code v1 Negative Vectors](cash-code-v1-negative-vectors.json)
- [RPA Compatibility Decision](rpa-compatibility-decision.md)
- [RPA Historical Scan Benchmark Gate](rpa-historical-scan-benchmark-gate.md)
- [Public API Guide](public-api.md)
