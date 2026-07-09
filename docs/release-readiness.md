# Release Readiness

This page tracks public-safe release posture for builders evaluating Opal Base. It does not create a release, tag a release, or change dependency requirements.

## Current Public Status

- Latest released tag: `v0.3.0`.
- Builder-review surface: public `develop` branch.
- Next possible release line: `v0.4.0`, not yet released.
- License posture for the next release notes: Apache License 2.0, matching the repository `LICENSE` file.

## Builder Review Versus SemVer Release

The public `develop` branch is acceptable for builder review when all SwiftPM dependency URLs are public and the tracked `Package.resolved` file does not expose private-only topology. It is not a SemVer release.

A true `v0.4.0` release should coordinate sibling package releases first, then move Opal Base dependencies to public tags/version requirements after explicit maintainer approval. Exact public revisions can support a review candidate, but coordinated tags are the preferred release state.

## Release Hardening Checklist

- Confirm `swift build` passes from a clean checkout.
- Confirm `swift test` passes from a clean checkout.
- Confirm optional live Fulcrum validation is either intentionally run or explicitly skipped: `OPAL_RUN_LIVE_NETWORK_TESTS=1 OPAL_FULCRUM_URL=<server> swift test --filter NetworkLiveSmokeValidator`.
- Confirm `Package.swift` and `Package.resolved` use only public dependency URLs and do not expose private-only branch topology.
- Decide whether sibling packages need public tags before the Opal Base release tag.
- Treat the license posture change from the older README's MIT claim to Apache License 2.0 as explicit release-note material.
- Confirm README, docs, changelog, package files, and license use strict Bitcoin Cash terminology and contain no private process artifacts.

## Documentation Readiness Checklist

- README gives builders a quick package role, install path, trust-boundary summary, quick start, docs map, validation commands, and release status.
- Starter guide gets a new BCH builder through wallet creation or restore, CashAddr receive-address reservation, Fulcrum sync, BCH balance/history/UTXO/confirmation refresh, and external-review spend preparation.
- Recipes document common tasks without forcing readers through advanced domains first.
- Trust boundaries make secret handling, descriptor-backed sync, `privateAccount` authoring, external signing review, Secure Enclave limits, and redacted diagnostics explicit.
- Public API guide maps facades in `Sources/OpalBase/Public` to the builder tasks they support.
- Architecture guide explains package boundaries relative to `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, `OpalHedge`, and `OpalDiagnostics`.

## Notes For Release Notes

- Call out that Opal Base is Bitcoin Cash-specific and uses strict BCH terminology: Bitcoin Cash, BCH, CashAddr, satoshi/satoshis, transaction output, UTXO, confirmed, and unconfirmed.
- Call out the Apache License 2.0 license posture if prior public-facing docs claimed MIT.
- Call out dependency hardening status clearly if the release candidate still uses branch-based sibling package dependencies.
