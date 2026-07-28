# Release Readiness

This page tracks public-safe release posture for builders evaluating the Opal Base `v0.4.1` release line. It does not create a release, tag a release, or change dependency requirements.

## Current Public Status

- Release line: `v0.4.1`.
- Previous public tag before this release line: `v0.4.0`.
- Builder-review surface between tags: public `develop` branch.
- Release source: annotated `v0.4.1` tag.
- Package version constant: `OpalBase.version == "0.4.1"`.
- License posture for release notes: Apache License 2.0, matching the repository `LICENSE` file.

## Builder Review Versus SemVer Release

The public `develop` branch is acceptable for builder review when all SwiftPM dependency URLs are public and the tracked `Package.resolved` file does not expose private-only topology. It is not a SemVer release.

The `v0.4.1` release candidate uses public sibling package URLs with public `develop` branch requirements and tracked `Package.resolved` revisions. Moving sibling dependencies from public `develop` branches to public SemVer tags is a separate maintainer-approved dependency change because it changes `Package.swift` dependency requirements.

## Release Hardening Checklist

- Confirm `swift build` passes from a clean checkout.
- Confirm `swift test` passes from a clean checkout.
- Confirm optional live Fulcrum validation is either intentionally run or explicitly skipped: `OPAL_RUN_LIVE_NETWORK_TESTS=1 OPAL_FULCRUM_URL=<server> swift test --filter NetworkLiveSmokeValidator`.
- Confirm `Package.swift` and `Package.resolved` use only public dependency URLs and do not expose private-only branch topology.
- Confirm the branch-based sibling dependency posture is accepted for this release, or explicitly approve a `Package.swift` dependency requirement change before promotion.
- Treat the license posture change from the older README's MIT claim to Apache License 2.0 as explicit release-note material.
- Confirm README, docs, changelog, package files, and license use strict Bitcoin Cash terminology and contain no private process artifacts.

## Validation Status

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
- Architecture guide explains package boundaries relative to `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, `OpalHedge`, and `OpalDiagnostics`.

## Notes For Release Notes

- Call out that Opal Base is Bitcoin Cash-specific and uses strict BCH terminology: Bitcoin Cash, BCH, CashAddr, satoshi/satoshis, transaction output, UTXO, confirmed, and unconfirmed.
- Call out the Apache License 2.0 license posture if prior public-facing docs claimed MIT.
- Call out dependency hardening status clearly if the release candidate still uses branch-based sibling package dependencies.
