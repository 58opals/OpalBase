# Mosaic G3 OpalBase Package-Facade Evidence — 2026-08-21

## Status

This document validates the OpalBase package slice needed by Mosaic G3. It does not close G3: Wallet still has to own and prove one composed application session, synchronous atomic companion-journal storage, protected purpose-separated keys, restart recovery, Tor route-loss handling, and terminal cleanup at an exact promoted dependency graph.

## Exact implementation and graph

- OpalBase implementation: `947b9fb3bc107eeb7eb6ea099a51314e021b7aef`
- OpalFusion: `95a8a35a6f3832ffc6409c862877aa1645da268d`
- OpalCrypto: `23425db04075a48405d65cf6a3e2254911e626eb`
- SwiftFulcrum: `24b44bb2458822d14121dfbd57321fda7ae539ea`
- OpalDiagnostics: `7cd2e383309821e01903077c1e534174f9c8a964`

`Package.resolved`, each SwiftPM checkout, and each direct dependency's public `develop` head identified the revisions above during the remote dependency-doctor run.

## Proven package boundary

- App-facing fresh creation takes a Base-owned 32-byte triplet binding and constructs the frozen mainnet-alpha.4 Fusion attempt internally.
- App-facing recovery takes the same Base binding plus opaque authenticated Fusion recovery bytes; neither constructor exposes a Fusion type.
- One Base actor retains the sole Fusion owner, exact wallet transaction host, and the same transaction reader used as previous-output authority.
- Contributor and conductor construction restore package-authenticated mailbox documents and adapt only Base-owned app capabilities for synchronous companion-journal compare-and-swap, timing, Tor route provisioning, anonymous-publication pacing, protected slot secrets, and purpose-separated conductor keys.
- Runtime, wallet-recovery, and transport failures return recovery-required dispositions. Only package-authenticated completion or abort can produce terminal evidence, and that evidence is correlated back to the exact Base binding before it is returned.
- Actor reentrancy cannot begin two execution constructions concurrently; a second in-flight construction request fails with `operationInProgress`.

## Validation evidence

- `swift test` on one shared custom SwiftPM lane built successfully, then passed 37 network-target tests in 10 suites and 1,045 local tests in 112 suites with zero failures. Live-network flags were not enabled.
- The focused Mosaic aggregate passed 41 tests in 12 suites. Within it, the application facade passed 2/2, runtime adapter 9/9, recovery owner 13/13, and post-manifest bridge 1/1.
- `swift test list` completed successfully and discovered the new application-facade and post-manifest bridge validators.
- A separate Swift 6.4/macOS 26 source file typechecked against the built module while importing only Foundation and the OpalBase private-alpha SPI. It constructed the Base binding, journal, relay, timing, and combined runtime capabilities without importing OpalFusion or OpalCrypto; the temporary source was removed afterward.
- SPI-inclusive symbol-graph extraction succeeded. The new application constructors and post-manifest facade contain no Fusion-typed public signature. Two older module-wide SPI symbols still name Fusion types (`TransactionReader.resolvePreviousOutputs(for:)` and `BroadcastApprovalRequest.profile`); they are outside the new constructor/capability path, do not require a direct Wallet package dependency, and remain cleanup work before any public API claim.
- `git diff --check` passed.

## Non-claims and remaining work

This evidence contains no live external networking, mainnet broadcast, value movement, anonymity claim, public enablement, or release-readiness claim. It proves a package boundary at the exact graph above, not an application-composed Mosaic session. G3 remains open until Wallet provides fresh-process, crash-cut, restart, Tor-only route-loss, recovery-required, and exact terminal-cleanup evidence without directly declaring or linking OpalFusion.
