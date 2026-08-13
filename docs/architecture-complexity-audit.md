# OpalBase Architecture Complexity Audit

Status date: 2026-08-13. Audit base: private `draft` at `62af54251b94a649d73d479cb7c8e1ba5a4f3451`. This report covers two bounded P1 simplifications; it does not claim release readiness, live Mosaic support, or completion of the Cash Code production gates.

## Verdict

The package boundary is structurally sound. OpalCrypto owns reusable cryptographic computation, OpalFusion owns collaborative protocol and transport semantics, and OpalBase owns wallet/account state, persistence, spend authorization, transaction construction, approval, and broadcast. The two P1 defects were local authority splits: secret-write behavior could change by convenience overload, and copies of a Cash Code spend plan could independently build competing random-nonce transactions. Both now have one owner.

## Measured Baseline and Result

The base contained 403 production Swift files and 37,667 production lines, plus 212 test Swift files and 43,387 test lines. The cleanup leaves 403 production files and 37,721 production lines, plus 214 test files and 43,823 test lines. The 54-line production increase is the net result of deleting storage defaults, Boolean fallback adapters, policy-translation overloads, and per-call policy entry points while adding the Cash Code lifecycle actor and its public failure contract. Test growth separates the fixture-light lifecycle proof from existing real random-nonce signing and verifies cancellation ownership and every construction-bound custom policy.

## Ownership Map

| Concern | Authoritative owner | Preserved boundary |
| --- | --- | --- |
| Cryptographic primitives | OpalCrypto | OpalBase selects BCH transaction and wallet policy but does not duplicate scalar, signing, or verification engines. |
| Collaborative protocol execution | OpalFusion | OpalBase supplies narrow wallet-host capabilities; it does not own CashFusion or Mosaic wire state. |
| Wallet and account lifecycle | OpalBase wallet/account actors | Reservation, signing authority, persistence, approval, and broadcast remain app-facing wallet concerns. |
| Secret-write policy | One `Storage` or manually composed `StoredMnemonicPersistence` root | Existing plaintext and historical Secure Enclave envelopes remain readable; only the construction-bound policy controls new writes. |
| Cash Code sender lifecycle | One `CashCodeSpendPlanLifecycle` actor retained by every plan copy | The plan admits one valid build and one terminal reservation disposition; build failure and task cancellation release automatically. |
| Cash Code broadcast decision | Integrating application | A successful build remains separate from relay acceptance and the caller's complete-or-cancel decision. |

## Applied Findings

1. **P1 resolved — secret persistence had multiple policy authorities.** `Storage` no longer defaults to an in-memory backend or plaintext security, and `Security` no longer accepts absent encrypt/decrypt closures. A storage or custom mnemonic-persistence root now requires one immutable `PersistencePolicy`, and a custom backend receives only that bound policy. Boolean fallback adapters, per-save policy overrides, and the policy/profile overloads on the secret interactor were deleted. `makeSecureEnclaveBacked` binds `.requireSecureEnclave`; `.legacyFallbackToPlaintext` remains explicit and migration-only. Stored bytes, canonical keys, historical loading, strict weak-write rollback, generation commits, recovery tolerance, and protected-material reset are unchanged. The source break is classified for the next explicitly breaking pre-1.0 release with migration instructions in the public API guide; no insecure compatibility default is retained.
2. **P1 resolved — Cash Code plans were copyable build authorities.** Every plan copy retains the same actor. Invalid attempt bounds fail before lifecycle admission or signing. The first valid build excludes concurrent and repeated builds; lifecycle-owned cancellation checks surround the candidate operation; failure or cancellation performs one cancellation-free reservation release before rethrowing; a successful build admits exactly one completion or cancellation; and a failed disposition terminalizes as uncertain rather than retrying a possibly applied address-book effect. Public method signatures remain unchanged, while the catchable nested `LifecycleError` makes uncertain disposition distinct from ordinary reuse.
3. **Validation split resolved.** `CashCodeSpendPlanLifecycleValidator` injects build and disposition probes and creates no signing key. `CashCodeSenderRealCryptoConformanceValidator` retains the production random-Schnorr-nonce smoke path under an explicit five-minute integration limit. A successful real grind plus Bitcoin Cash virtual-machine verification remains a release milestone because this package has no BCH VM dependency.

## Deferred Findings and Reopen Signals

1. **P2 — disabled live tests report ordinary passes.** Reopen when Swift Testing enablement or skip semantics can replace the 37 environment guard-returns without contacting a network in default validation. Stop after both live flags are documented and disabled discovery is visibly classified. Budget: test discovery, one disabled smoke filter under five seconds, and no live request.
2. **P2 — Mosaic recovery has Boolean lifecycle state and an oversized mixed validator.** Reopen when the recovery gate can move to one `ready/recovering/issued` enum without changing quarantine or issuance order. Stop after splitting planner, authenticated journal, recovery gate, and broadcast coordinator tests along existing owners. Budget: build, discovery, each focused suite under ten seconds, and no network.
3. **P2 — test targets rely on transitive products.** Reopen when direct `OpalCrypto`, `SwiftFulcrum`, and `OpalDiagnostics` test imports can be declared without changing resolved revisions. Stop after manifest ownership is explicit. Budget: build, discovery, one dependency compatibility filter under 15 seconds, and an unchanged `Package.resolved`.
4. **P2 — validation and status documentation is duplicated.** Reopen after the three P1 audits have landed. Stop when README contains only stable status and links, architecture contains only stable ownership, validation commands have one source of truth, and release-readiness counts are explicitly dated snapshots. Budget: documentation consistency check and link validation; no implementation change.
5. **P3 — snapshot DTO helpers, CashFusion mirrors, and small network protocols.** Reopen only after an observed divergence, repeated maintenance change, or measured performance problem identifies one concrete owner to remove. Do not create a generic repository, workflow, or transport framework for speculative reuse.

## Validation Contract

The focused Cash Code lifecycle filter must stay below 15 seconds after a warm build and must not create signing keys. Storage-policy validation may use the existing EC/Secure Enclave conformance cases but must not contact a network. The real random-nonce Cash Code suite is explicitly slow and capped at five minutes; a successful grind plus BCH VM execution remains deferred to release milestone validation. Full local validation excludes opt-in Fulcrum tests. Dependency revisions and `Package.resolved` must remain unchanged.

The cleanup build passed in 19.33 seconds and test discovery passed in 17.36 seconds. The generation-free lifecycle filter executed its initial two-test shape in 0.001 seconds before the final cancellation cases were added; the final four-test shape passed within the full deterministic local run and remains statically free of signing-key construction. The corrective closeout run built in 20.01 seconds and passed 1,002 local tests across 97 suites in 93.597 seconds. Its first invocation stopped before test execution on a same-file Swift access-level error; one `private`-to-`fileprivate` correction was applied before the passing run. No live Fulcrum request or slow random-nonce conformance run was made.
