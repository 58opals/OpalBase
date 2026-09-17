# Local Mosaic wallet integration

Mosaic is an experimental macOS-only SPI for a wallet-owned collaborative BCH transaction. It is useful to builders who need explicit input ownership, signing validation and restart reconciliation while evaluating peer-conducted coordination. It is not an enabled live service or a claim of production privacy.

Import `@_spi(MosaicPrivateAlpha) import OpalBase` in the application integration layer. Use `MosaicPrivateAlphaRuntime.createFreshApplicationSessionOwner(...)`, or create a `FreshHost` with `createFreshApplicationHost(account:...)` and claim `makeSessionOwner()` exactly once. For restart, pass the original authenticated recovery inputs to `loadApplicationSessionRecovery(...)`. The `SessionOwner` retains the sole Fusion owner and Base transaction host; do not create a parallel protocol coordinator.

## Ownership and durability

1. Supply exact previous transactions, selected wallet inputs, output amounts and journal persistence. Base plans receiving entries. A prepared request claims the host before any awaited address preparation. A concurrent request cannot replace it.
2. Reservation transfers selected inputs into an attempt/generation-scoped quarantine. Receiving entries have the same scoped ownership. Generic input release, reservation resets and address updates cannot release that ownership. An observed receiving address may become used while remaining reserved.
3. Persist every requested transition. Fusion recovery persistence returns exact durable bytes; Base journal persistence atomically compares and exchanges the exact envelope and returns a success boolean. A failed or ambiguous write retains ownership until authenticated recovery resolves it. Only after output retirement and the released journal are durable may inputs become spendable again.
4. Supervise `SessionOwner.expiryUnixSeconds` after constructing post-manifest execution. `stopIfExpired(currentUnixSeconds:)` stops execution strictly after the inclusive final deadline. Then claim `waitForDisposition` once and preserve a recovery-required outcome. Stopping is neither a signed abort nor authority to release funds.
5. Authenticate a terminal protocol disposition before wallet recovery or exact transaction commit. Recover an already persisted terminal state through the existing zero-route restoration path even after the live deadline. That authenticated terminal-only path revalidates archived mailbox documents within the proof's signed original window; it retains every signature, identity and terminal-companion check. Live admission and the runtime clock remain current. Broadcast remains a separate, explicitly approved application operation. Terminal restoration does not renew the original reservation or grant a new broadcast approval window after its expiry; the application must retain the recovered state when approval is denied.

Snapshot refresh is rejected while the address book owns Mosaic output reservations. This avoids replacing live ownership with a stale snapshot. After a process restart, load a fresh book from the wallet snapshot and replay the authenticated Mosaic journal before exposing its selected inputs to ordinary spending. The journal, not a snapshot boolean, identifies the original reservation and generation. Recovery rejects overlapping generic reservations and different owners rather than releasing them.

The `Tests/OpalBaseLocalTests/AccountMosaic*` validators show public synthetic inputs, exact signing/transaction checks, ambiguous write recovery, cancellation, foreign reservations and fresh-book restart. Existing journal and protocol versions remain unchanged. Applications must keep their own persisted compatibility identities distinct from fingerprints of a new validation candidate.

## Reproduce locally

Use Swift 6.4 and macOS 27 with the Metal toolchain. For an unpublished matching Fusion candidate, use SwiftPM edit mode before testing:

```sh
swift package resolve
swift package edit OpalFusion --path /absolute/path/to/OpalFusion
swift test --filter 'AccountMosaicTransactionHostValidator|AccountMosaicPrivateAlphaRecoveryOwnerValidator'
swift test --no-parallel
```

Use the same scratch/cache paths for every command when isolating the build. Do not combine edit mode with forced resolved-file-only dependency resolution: verify the workspace state's edited path and the build's actual source paths. Preserve the exact Crypto, Diagnostics and SwiftFulcrum lock revisions. Leave live-network opt-in variables unset. The tests use public fixture keys and must never hold value.

Formation still needs 7–9 candidates including a noncontributing conductor, with a 300-second discovery epoch. Synthetic participants do not demonstrate operator independence. Amount linkage, collusion, Sybil participation, traffic metadata and selective abort remain limitations. The accepted off-commitment vector limits accountability; it is not proof of authorized component membership. External protocol/cryptographic and wallet-recovery review, independent environments and separately authorized deployment evidence remain outstanding.
