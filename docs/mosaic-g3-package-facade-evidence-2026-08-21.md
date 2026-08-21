# Mosaic G3 OpalBase Package-Facade Evidence — 2026-08-21

## Status

This document validates the OpalBase package slice needed by Mosaic G3. It does not close G3: Wallet still has to own and prove one composed application session, synchronous atomic companion-journal storage, protected purpose-separated keys, restart recovery, Tor route-loss handling, and terminal cleanup at an exact promoted dependency graph.

## Exact implementation and graph

- OpalBase implementation: `99973f7920aa474ff2b0d85720e6b2a5aba35c0b`
- OpalFusion: `95a8a35a6f3832ffc6409c862877aa1645da268d`
- OpalCrypto: `23425db04075a48405d65cf6a3e2254911e626eb`
- SwiftFulcrum: `24b44bb2458822d14121dfbd57321fda7ae539ea`
- OpalDiagnostics: `7cd2e383309821e01903077c1e534174f9c8a964`

`Package.resolved`, each SwiftPM checkout, and each direct dependency's public `develop` head identified the revisions above during the remote dependency-doctor run.

## Proven package boundary

- App-facing fresh creation takes a Base-owned 32-byte triplet binding, constructs the frozen mainnet-alpha.4 Fusion attempt internally, and persists and exactly reads back its mandatory initial recovery transition before claiming the Base journal attempt or writing the wallet binding.
- App-facing recovery takes the same Base binding plus opaque authenticated Fusion recovery bytes; neither constructor exposes a Fusion type.
- One Base `SessionOwner` actor retains the sole Fusion owner, exact wallet transaction host, and the same transaction reader used as previous-output authority across formation, recovery, and post-manifest execution.
- After that bootstrap transition, fresh formation durably persists and exactly reads back each replacement state before installing the opaque pool and relay-set documents. Every discovery, candidate-set, admission, role-election, nonce-allocation, manifest, and pre-manifest-abort transition is exposed only through Base-owned inputs and progress values.
- Copies of a fresh or recovered host share one asynchronous owner claim, and copies of signing material share one asynchronous one-use claim. A second claim fails before a second owner or signature capability can be minted.
- Contributor and conductor construction restore package-authenticated mailbox documents and adapt only Base-owned app capabilities for synchronous companion-journal compare-and-swap, timing, Tor route provisioning, anonymous-publication pacing, protected slot secrets, and purpose-separated conductor keys.
- Runtime, wallet-recovery, and transport failures return recovery-required dispositions. Only package-authenticated completion or abort can produce terminal evidence, and that evidence is correlated back to the exact Base binding before it is returned.
- Actor reentrancy cannot overlap formation, recovery advancement, or execution construction. A second in-flight session operation fails with `operationInProgress`, including while the first operation is suspended on app-owned durable persistence.

## Validation evidence

- `swift build` succeeded on the same SwiftPM lane used for validation. `swift test` then passed 37 network-target tests in 10 suites and 1,046 local tests in 112 suites with zero failures; live-network flags were not enabled.
- The complete Mosaic-focused selection passed 42 tests in 12 suites. Within it, the application facade passed 3/3, including a direct observation that the wallet journal is still empty while the initial Fusion recovery transition is persisted, exact persistence and readback, local relay publication, restart from the exact opaque snapshot, shared one-use claims, and actor-reentrancy rejection while a later persistence transition was suspended.
- `swift test list` completed successfully and discovered the new application-facade and post-manifest bridge validators.
- A separate Swift 6.4/macOS 26 source file typechecked against the built module while importing only Foundation and the OpalBase private-alpha SPI. It claimed fresh and recovered session owners and called the Base-owned begin/resume surface without importing OpalFusion or OpalCrypto; the temporary source was removed afterward.
- SPI-inclusive symbol-graph extraction succeeded. Every new public-SPI session, formation, recovery, and post-manifest signature is Base-owned and contains no OpalFusion type. Older raw-Fusion signatures outside this new facade remain cleanup work before any public API claim.
- The pinned dependency doctor matched `Package.resolved`, each shared-lane checkout, and each direct dependency's remote `develop` head for OpalCrypto, OpalDiagnostics, OpalFusion, and SwiftFulcrum.
- `git diff --check` passed.

## Complexity decision

The full-session facade is intentionally a direct phase API rather than a generic command enum or parallel state machine. OpalFusion remains the only protocol-state owner; OpalBase adds one transition driver for persistence, publication, recovery directives, duplicate handling, and terminal evidence. Fresh application creation reuses that sole owner after its bootstrap persistence handshake and only then enters the existing journal-construction path; it does not add a second owner, state machine, or recovery format. The repeated public methods preserve phase-specific call-site labels and one-use signing boundaries without duplicating transition logic. Legacy post-manifest owner aliases were removed instead of keeping two facade families.

## Non-claims and remaining work

This evidence contains no live external networking, mainnet broadcast, value movement, anonymity claim, public enablement, or release-readiness claim. It proves a package boundary at the exact graph above, not an application-composed Mosaic session. The corrected bootstrap ordering lets Wallet precreate an authenticated empty outer record: a crash before the wallet binding remains cleanup-authorizable, while every crash after the binding has both the exact Fusion snapshot and Base journal recovery state. G3 remains open until Wallet proves those crash cuts plus fresh-process, restart, Tor-only route-loss, recovery-required, and exact terminal-cleanup behavior without directly declaring or linking OpalFusion.
