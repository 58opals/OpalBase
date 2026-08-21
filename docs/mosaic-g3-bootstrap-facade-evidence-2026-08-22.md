# Mosaic G3 OpalBase Bootstrap-Facade Evidence — 2026-08-22

Status: validated producer-repository follow-up for the Wallet G3 consumer. This document does not close G3; Wallet still has to pin the promoted revision and prove one app-owned session through authenticated bootstrap, exact host commit, process restart, recovery-required transport loss, and zero broadcast.

## Exact Implementation And Dependency Graph

The implementation revision is OpalBase `2a3f44891e3d8658db30226e1a66c5c955b82168`.

| Package | Exact resolved revision | Lane |
| --- | --- | --- |
| OpalCrypto | `23425db04075a48405d65cf6a3e2254911e626eb` | `develop` |
| OpalDiagnostics | `7cd2e383309821e01903077c1e534174f9c8a964` | `develop` |
| OpalFusion | `6eaa797df1bcaa5fa89ada580d1ce2c1670e0722` | `develop` |
| SwiftFulcrum | `24b44bb2458822d14121dfbd57321fda7ae539ea` | `develop` |

## Boundary Proven

- The sole Base-owned `SessionOwner` projects the authenticated private-deployment roster and every canonical authorization-key, control-claim, blind-response, anonymous-registration, assignment, registration-set, and acknowledgement document needed to construct or restore bootstrap state.
- Seal and open operations retain OpalFusion's exact NIP-59 validation, binding, proof, reserved-identity, and timestamp inputs while returning only Base-owned SPI values. Durable publication restoration and retry preserve the exact canonical event, operation identifier, and accepted-relay evidence.
- The Base-owned inbox wraps OpalFusion's exact-three-source actor without a second forwarding task or buffer. Its custom async sequence maps each replay-preflighted event at iteration time, so the package-owned bounded queue and termination behavior remain authoritative.
- One operation gate now owns session-state checks, proof acquisition, cancellation preservation, and redacted error mapping for all bootstrap operations. Opened-envelope metadata projection is centralized, and conductor archive assembly rejects duplicate registrations, duplicate assignment-to-registration mappings, missing mappings, and count mismatches before persistence.
- Every document wrapper retains the validated package value behind internal immutable storage while exposing only the exact canonical bytes and app-required typed fields. No new exported declaration contains an OpalFusion type.
- `OpalBaseTestSupport` compiles a permanent transport-bootstrap consumer while depending on OpalBase but not OpalFusion. This guards the intended application dependency policy independently of the local test target, which directly depends on OpalFusion for package integration tests.

## Complexity Decision

The phase-specific methods are intentionally retained instead of replacing the protocol with a generic command enum, erased document container, or second state machine. They preserve call-site labels and compile-time document ordering while OpalFusion remains the only wire-state owner. The review removed accidental layers: proof acquisition is centralized, opened-publication projection is centralized, the duplicate inbox buffer and forwarding task are absent, and no speculative fallback or parallel owner was added.

## Validation

- `swift build` passed after the final boundary and stream changes.
- `swift test --filter AccountMosaicPrivateAlphaApplicationFacadeValidator` passed 3 tests in 1 suite. The compile-only consumer target was built as part of that command without an OpalFusion dependency.
- `swift test` passed 1,048 tests in 112 suites after the final changes. The default network target also passed 37 tests in 10 suites with live flags disabled; no external relay, Tor, Fulcrum staging, or broadcast session was used.
- An SPI-inclusive symbol graph was extracted from the built OpalBase module with the Xcode 27 Swift 6.4 toolchain. Filtering every new `TransportBootstrap` declaration for `OpalFusion` returned zero matches.
- `git diff --check` passed.

## Remaining G3 Work

This package slice deliberately does not duplicate OpalFusion's real-RSABSSA transcript fixture. The next evidence must come from Wallet as the actual consumer: pin the promoted Base revision, persist role-specific bootstrap archives and purpose-separated keys in the authenticated outer record, exercise the facade through the production Tor/relay adapters in the approved local deterministic harness, reach exact host commit without broadcast, restart from durable state, and demonstrate the correct recovery or approval-required outcome. Live external networking, mainnet broadcast, value movement, public enablement, and release claims remain separately gated.
