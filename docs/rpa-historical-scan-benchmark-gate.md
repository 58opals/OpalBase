# RPA Historical Scan Benchmark Gate

## Decision

The production-implementation gate is satisfied, but the release benchmark gate remains closed. Do not add or publish a historical Cash Code benchmark until it can exercise a production-representative Fulcrum RPA index and raw-transaction service through the real `Network.Fulcrum.ReusablePaymentAddressReader`, `Network.TransactionReader`, `CashCodeInteractor`, and generation-staged storage path.

The deterministic local test corpus intentionally uses actor-backed transport and persistence doubles to prove correctness. Timing those injected closures, preloaded transactions, the matcher alone, or an invented wallet lifecycle would not measure production restoration and is not an acceptable release benchmark.

## Implemented Production Path

Cash Code v1 now has the concrete lifecycle that the earlier gate required:

- `Network.ReusablePaymentAddressReader` is a transport-neutral candidate boundary with a production Fulcrum adapter and distinct confirmed/mempool reference types.
- `ReusablePaymentAddress.Transport` keeps candidate lookup separate from the hash-validating raw-transaction reader.
- `CashCodeInteractor.openRestoration(for:keyOrigin:restoreStartHeight:scanSigningKey:spendSigningKey:)` creates or resumes an exactly bound, authorized restoration actor.
- Confirmed restoration uses bounded half-open windows, rejects out-of-window and conflicting references, deduplicates exact references, independently checks raw transaction hashes, matches exact serialized transactions, and atomically commits the complete window plus cursor.
- Cancellation before commit leaves the current window unapplied; restart resumes at `nextUnscannedHeight`; replay does not duplicate outputs.
- Mempool refresh atomically replaces the verified unconfirmed snapshot, removes stale entries, gives confirmed outpoints precedence, and handles confirmation transitions deterministically.
- Trusted reorganization intake removes affected confirmed outputs, rewinds to the bounded safe height, stores a bounded history of event identifiers for durable idempotence, and reuses confirmed restoration for deterministic replay.
- `Storage.makeReusablePaymentAddressStatePersistence(identifier:)` hashes the registration identifier, generation-stages complete state, commits through a generation marker, coordinates process-wide operations, and checks expected revisions.
- Durable state contains the exact Cash Code profile/network/public-key/key-origin binding, restore start, cursor, public derivation context, exact matched-output BCH and CashToken data, confirmed/mempool separation, revision, and reorganization metadata. It excludes signing capabilities, complete Cash Codes/paycodes, filter prefixes, shared material, and raw transactions.
- A matched output remains distinct from a UTXO until `confirmUnspentOutput(for:using:)` verifies the exact current outpoint payload.

The deterministic Swift Testing corpus covers bounded windows, duplicate and conflicting references, raw hash mismatch, atomic failure, cancellation, restart/resume, replay, mempool replacement, confirmation transitions, reorganization rollback and old-event idempotence, production state serialization, binding rejection, capability rederivation, exact UTXO confirmation, CashToken preservation, sender preparation, prefix success and exhaustion, cancellation, network/profile rejection, and the first-30-input limit.

## Why The Release Benchmark Gate Is Still Closed

No repository benchmark target currently owns a production-representative Fulcrum lifecycle. A valid benchmark needs either a controlled local Fulcrum instance built from a documented chain/index snapshot or a separately approved stable benchmark service with nonsecret workload registration. A closure-backed replay server would collapse network/index work into fixture lookup and would violate the benchmark objective.

The production code also does not expose phase timing solely for benchmark consumption. Adding timing hooks before a representative lifecycle exists would risk optimizing an invented workload and broadening diagnostics around wallet-identifying candidates.

## Remaining Entry Criteria

Open the release benchmark gate only when all of the following are true:

- a controlled Fulcrum endpoint exposes protocol 1.6 RPA capability values and deterministic confirmed and mempool data for the benchmark corpus;
- benchmark setup creates or resets an isolated temporary production storage backend outside timed regions;
- the timed path uses the real Fulcrum candidate reader, hash-validating transaction reader, restoration actor, matcher, and production state serializer/commit marker;
- fixture construction, server startup/indexing, key authorization, and expected-result calculation occur outside timed regions;
- correctness is asserted before every workload is sampled, including exact hashes, indices, BCH values, CashToken data, cursor, and reorganization result;
- no complete Cash Code, filter prefix, signing capability, raw wallet transaction, shared material, or wallet-identifying candidate appears in output; and
- the benchmark can run in release mode repeatably enough for medians and percentiles to be meaningful.

## Required Release Benchmark Shape

When those criteria are met, add a release-mode executable covering one small incremental confirmed scan, one maximum advertised history window, a multi-window restoration with restart, a mempool refresh after confirmed scanning, and a reorganization rollback followed by replay.

Measure Fulcrum candidate loading, raw transaction loading and hash verification, exact decoding and input qualification, shared-point and child-key derivation, output matching, state serialization and commit, and total wall time. Emit deterministic JSON Lines with a versioned schema, nonsecret workload identifier, workload sizes, sample count, median and percentile durations, match count, final cursor, and a nonsecret correctness digest.

Only recommend cryptographic optimization when the profile-compatible shared-point and child-key stage is both the largest measured stage and more than half of total representative restore time. Until a qualifying benchmark exists, OpalBase makes no historical-scan performance claim.
