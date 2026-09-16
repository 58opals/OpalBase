# Release Readiness

This page tracks the published Opal Base `v0.4.1` tag and the separate current `develop` integration surface. The tag is not resolvable as a SwiftPM version-based dependency. It does not create a release, tag a release, or change dependency requirements.

## Current Public Status

- Release line: `v0.4.1`.
- Previous public tag before this release line: `v0.4.0`.
- Builder-review surface between tags: public `develop` branch.
- Published source: annotated `v0.4.1` tag; publication does not establish downstream version-based installability.
- Package version constant: `OpalBase.version == "0.4.1"`.
- License posture for release notes: Apache License 2.0, matching the repository `LICENSE` file.
- Cash Code v1 status: tracked under `Unreleased` and not included in `v0.4.1`; see [Cash Code v1 Readiness](cash-code-readiness.md) for its separate feature and release gates.

## Builder Review Versus SemVer Release

The public `develop` branch is acceptable for builder review when all SwiftPM dependency URLs are public and the tracked `Package.resolved` file does not expose private-only topology. It is not a SemVer release.

The published `v0.4.1` manifest uses public sibling package URLs with `develop` branch requirements. SwiftPM rejects that graph when a consuming package requests a stable version of Base. A package's tracked `Package.resolved` is not a substitute for compatible version requirements. Use the [revision-based installation example](../README.md#installation) for current integration testing and retain the consumer's resolved revisions.

A future version-consumable release requires compatible published sibling versions, approved version requirements in `Package.swift`, and a clean downstream consumer-resolution check against the proposed release graph. This work changes dependency contracts and release readiness; it cannot be satisfied by accepting the existing branch topology or retagging `v0.4.1`.

## Release Hardening Checklist

- Confirm `swift build` passes from a clean checkout.
- Confirm `swift test` passes from a clean checkout.
- Confirm optional live Fulcrum validation is either intentionally run or explicitly skipped: `OPAL_RUN_LIVE_NETWORK_TESTS=1 OPAL_FULCRUM_URL=<server> swift test --filter NetworkLiveSmokeValidator`.
- Confirm `Package.swift` and `Package.resolved` use only public dependency URLs and do not expose private-only branch topology.
- For a SemVer-consumable release, require compatible stable sibling requirements and verify a fresh consumer resolves Base by version. Record the exact graph and result before promotion; public branch URLs alone are insufficient.
- Treat the license posture change from the older README's MIT claim to Apache License 2.0 as explicit release-note material.
- Confirm README, docs, changelog, package files, and license use strict Bitcoin Cash terminology and contain no private process artifacts.

## Current Installability Evidence

On 2026-09-16, a disposable consumer requesting exact `0.4.1` from a local clone of the published repository failed resolution: Base was required by stable version but depended on unstable-version `SwiftFulcrum`. No package build ran. This reproduces the manifest restriction independently of a network fetch and leaves the published tag unchanged. Other sibling branch requirements must also be removed for a future stable graph.

## Historical Validation Status

- `swift build`: passed on 2026-07-29.
- `swift test`: passed on 2026-07-29 with 919 tests across 97 suites.
- Optional live Fulcrum validation: not run in the local suite because `OPAL_RUN_LIVE_NETWORK_TESTS` was unset.
- Public artifact guard: passed on 2026-07-11.
- Release-lane refs: live refs matched local tracking refs and the promotion path was fast-forwardable at validation time.
- Public `v0.4.1` tag: present as an annotated tag created on 2026-07-11.
- Dependency topology: `Package.swift` and `Package.resolved` use public GitHub URLs and public `develop` branch requirements for sibling Opal packages; no non-public dependency URL or draft branch requirement was found.

## Documentation Readiness Checklist

- README gives builders a quick package role, install path, trust-boundary summary, quick start, docs map, validation commands, and release status.
- Starter guide gets a new BCH builder through wallet creation or restore, CashAddr receive-address reservation, Fulcrum sync, BCH balance/history/UTXO/confirmation refresh, and external-review spend preparation.
- Recipes document common tasks without forcing readers through advanced domains first.
- Trust boundaries make secret handling, descriptor-backed sync, `privateAccount` authoring, external signing review, Secure Enclave limits, and redacted diagnostics explicit.
- Public API guide maps facades in `Sources/OpalBase/Public` to the builder tasks they support.
- Architecture guide explains package boundaries relative to `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, and `OpalDiagnostics`.
- Cash Code v1 readiness separates candidate-profile status, implementation completeness, production evidence, stable release availability, and ecosystem standardization.

## Notes For Release Notes

- Call out that Opal Base is Bitcoin Cash-specific and uses strict BCH terminology: Bitcoin Cash, BCH, CashAddr, satoshi/satoshis, transaction output, UTXO, confirmed, and unconfirmed.
- Call out the Apache License 2.0 license posture if prior public-facing docs claimed MIT.
- State the known version-consumer limitation for `v0.4.1`. Do not advertise a future tag as version-consumable until its stable dependency graph passes the downstream resolution gate.
