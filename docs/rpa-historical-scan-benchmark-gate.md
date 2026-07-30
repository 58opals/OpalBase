# RPA Historical Scan Benchmark Gate

## Decision

Do not add an OpalBase historical Reusable Payment Address (RPA) benchmark
target yet.

Cash Code v1 encoding, derivation, input qualification, and output matching now
have a byte-exact candidate contract and independent vectors. The remaining
blocker is no longer cryptographic ambiguity. It is the absence of a concrete,
durable historical-restore pipeline whose work and recovery behavior can be
measured honestly.

Do not benchmark injected closures, precomputed candidate transactions, the
stateless matcher alone, or an invented wallet lifecycle. None represents a
historical restore.

## Proven Production Primitives

The following components are suitable inputs to a future restore pipeline:

- [`cash-code-v1.md`](cash-code-v1.md) defines the versioned compressed-P2PKH
  candidate profile and its explicit legacy boundary.
- [`cash-code-v1-vectors.json`](cash-code-v1-vectors.json) and
  [`cash-code-v1-negative-vectors.json`](cash-code-v1-negative-vectors.json)
  contain deterministic, nonsecret encoding, derivation, transaction, token,
  and rejection vectors reproduced outside OpalBase.
- `ReusablePaymentAddress.Codec` strictly encodes Cash Code v1 and parses
  legacy Electron Cash `paycode:` values as read-only migration data.
- `ReusablePaymentAddress.derivePayment(from:spending:)` derives the sender
  destination for an explicit qualifying input key and outpoint.
- `ReusablePaymentAddress.Matcher.matches(in:for:scanSigningKey:spendSigningKey:)`
  exactly decodes one serialized transaction, examines at most its first 30
  inputs, derives compressed P2PKH locking bytecode, and retains the original
  matching output including CashToken data.
- `Network.Fulcrum.ReusablePaymentAddressReader` returns confirmed and mempool
  candidate transaction references through distinct types.
- SwiftFulcrum validates protocol 1.6 negotiation, advertised RPA capabilities,
  prefix limits, history limits, and method responses before OpalBase mapping.
- OpalCrypto provides the exact 32-byte shared-point x-coordinate operation
  and explicit-chain-code non-hardened CKDpub/CKDpriv operations required by
  the vectors. The opaque `SigningKey` path does not export private-key bytes.

The legacy `deriveSharedSecrets(privateKey:publicKeys:)` API is not compatible
with Cash Code v1: it hashes compressed SEC1 shared-point serialization.
A future benchmark MUST use the profile-compatible x-coordinate operation and
MUST NOT substitute that legacy batch API.

## Current Data Flow

The implemented components can be composed as follows:

```text
Cash Code v1
    -> derive 16-bit FilterPrefix
    -> fetch confirmed references or mempool references from Fulcrum
    -> fetch and hash-verify each referenced serialized transaction
    -> Matcher validates exact decoding, qualifying inputs, and prefix
    -> derive receiving signing capability and exact P2PKH locking bytecode
    -> retain matching transaction output and CashToken data
```

OpalBase does not yet own a production operation that performs this sequence
over historical block windows, commits the results, resumes after
cancellation, or rolls them back after a chain reorganization.

## Missing Restore Boundary

The benchmark gate remains closed until a production restore path defines and
implements all of the following:

- wallet-authorized access to the exact Cash Code v1 scan and spend signing
  capabilities and their persisted key origin;
- an explicit recovery start height and bounded confirmed-history windows that
  respect the server’s `starting_height`, `history_block_limit`, and
  `max_history` values;
- separate confirmed-history and mempool processing;
- hash-verified raw transaction loading for every candidate reference;
- deterministic deduplication of transaction references and matched outputs;
- an idempotent match repository that preserves the full decoded output and
  the metadata required to recover its receiving key;
- a durable last-completed-window cursor;
- cancellation and partial-window semantics that cannot advance the cursor
  past uncommitted work;
- restart/resume behavior;
- chain-reorganization rollback and replay behavior; and
- privacy-safe diagnostics that omit complete Cash Codes/paycodes, filter
  prefixes, raw wallet transactions, shared material, private keys, and
  wallet-identifying candidates.

Wallet owns consent, secret storage, scheduling, migration UX, and application
lifecycle. OpalBase should own the deterministic restore operation and its
persistence-facing contracts so a wallet integration and the benchmark execute
the same core behavior.

## Required Correctness Corpus

Before timing is accepted, extend the current per-transaction corpus with
deterministic restore cases covering:

- multiple confirmed windows and the advertised window boundary;
- a server history-limit failure;
- duplicate references across retries;
- confirmed and mempool versions of the same transaction;
- cancellation before and after an atomic window commit;
- resume from the last completed window;
- idempotent replay;
- a chain reorganization that removes and replaces matches; and
- a mixture of positive, prefix-miss, nonqualifying, malformed, and
  CashToken-bearing transactions.

Correctness tests MUST assert exact transaction hashes, input and output
indices, locking bytecode, BCH values in satoshis, CashToken data, cursor
state, and reorganization results before performance samples are collected.

## Benchmark Entry Criteria

The gate opens only when all of these statements are true:

- the concrete restore orchestrator uses the production Fulcrum reader,
  transaction reader, Cash Code matcher, and persistence boundary;
- the deterministic restore corpus passes end to end;
- confirmed/mempool separation, cancellation, resume, idempotency, and
  reorganization behavior are covered;
- the benchmark can use an isolated temporary store while executing the same
  serialization and commit path as production;
- fixture construction and server simulation are outside timed regions; and
- no secret or wallet-identifying material enters benchmark output.

## Release Benchmark Shape

When the gate opens, add a release-mode executable covering:

- one small incremental confirmed scan;
- one maximum advertised history window;
- a multi-window historical restore; and
- a mempool refresh following a completed confirmed scan.

Measure candidate loading, raw transaction loading and verification,
transaction decoding, qualifying-input filtering, shared-point and child-key
derivation, output matching, persistence, and total wall time separately.
Emit deterministic JSON Lines with a versioned schema, workload sizes, sample
counts, median and percentile durations, match count, and a nonsecret
correctness digest.

Only recommend further cryptographic optimization when the compatible
shared-point and child-key stage is both the largest measured stage and more
than half of total wall time in representative bulk restores. Until then,
there is no evidence-backed performance claim.

## Next Prerequisite

The next safe gate is the durable OpalBase restore boundary: window/cursor
semantics, an idempotent match repository, and reorganization behavior using
the already-proven Cash Code v1 primitives. Historical restore implementation
and benchmarking remain outside the current task.
