# RPA Historical Scan Benchmark Gate

## Decision

Do not add an Opal Base reusable payment address (RPA) benchmark target yet.
The package does not contain a concrete historical scan or restore pipeline, so
timing the current closure-backed seams would not measure product behavior.

No shared-secret wall-time percentage or optimization recommendation can be
reported until the pipeline below exists. In particular, the presence of
`OpalCrypto.Secp256k1.deriveSharedSecrets(privateKey:publicKeys:)` does not show
that shared-secret derivation dominates an Opal Base restore workload.

## Current Call Graph

The complete scanner path in production source is:

```text
ReusablePaymentAddress.Scanner.scan
    -> injected performScan closure
```

The complete candidate-reader path in production source is:

```text
ReusablePaymentAddressCandidateReader.fetchCandidateTransactions
    -> validate sinceBlockHeight
    -> injected performFetchCandidateTransactions closure
```

There are no production constructions or calls of either façade. The scanner
is constructed and invoked only by
`ReusablePaymentAddressScannerValidator`; the candidate reader is constructed
and invoked only by `ReusablePaymentAddressCandidateReaderValidator`. The
reader's internal protocol initializer has no concrete transport-backed
caller.

Other evidence that this is a contract scaffold rather than a scan pipeline:

- `Package.swift` has library, test-support, local-test, and network-test
  targets, but no benchmark executable.
- The default RPA codec throws `specificationUnavailable`; there is no selected
  compatibility profile or concrete paycode behavior.
- SwiftFulcrum integration decodes `server.features().rpa` capability metadata,
  but Opal Base has no adapter for confirmed RPA history or mempool candidate
  queries.
- No Opal Base source calls
  `OpalCrypto.Secp256k1.deriveSharedSecrets(privateKey:publicKeys:)`.
- `CandidateTransaction`, `ReceiveCandidate`, `ReceiveResult`,
  `BackupMetadata`, and `ScanKeyDescriptor` are standalone values. No
  orchestrator turns a wallet birthday into candidate windows, prepares input
  public keys, derives shared secrets, matches transaction outputs, or resumes
  a restore.
- There is no RPA scan cursor, match repository, address/index mutation, or
  persistence integration.
- The current fixtures establish type contracts only. For example, their raw
  transaction payload is two bytes and their locking script is a one-byte
  placeholder; they do not represent a decodable RPA transaction corpus with
  known positive and negative matches.

## Integration Ownership

The missing behavior crosses package boundaries, but it is not implemented in
another layer today.

| Concern | Owner |
| --- | --- |
| Ordered secp256k1 shared-secret primitive | OpalCrypto |
| Low-level RPA history and mempool protocol transport | SwiftFulcrum or another concrete indexer adapter |
| RPA compatibility profile, candidate decoding, scan orchestration, matching, BCH locking-script derivation, and reusable persistence contracts | Opal Base |
| Scan-key storage policy, user consent, background scheduling, restore UX, and app lifecycle | Integrating wallet app |

An end-to-end Opal Base benchmark becomes honest only after Opal Base owns the
real orchestration and calls concrete adapters at the transport and persistence
boundaries. A wallet app may supply those adapters and lifecycle policy, but a
benchmark must not replace them with closures that return precomputed results.

## Minimum Implementation Plan

### 1. Select And Prove One Compatibility Profile

- Choose the exact deployed RPA behavior to support, including compressed-key
  rules, prefix construction, expiration behavior, scan/spend key derivation,
  output matching, and restore semantics.
- Add vetted vectors for paycode parsing, input qualification, shared-secret
  use, derived locking scripts, positive matches, and negative matches.
- Define confirmed-history, unconfirmed mempool, block-window, duplicate,
  cancellation, and chain-reorganization behavior.

This step must precede scanner implementation; otherwise the benchmark would
encode an unreviewed protocol guess.

### 2. Implement Concrete Candidate Loading

- Add the required confirmed-history and mempool methods to SwiftFulcrum, or
  define an equivalent indexer client with the same production semantics.
- Adapt that client to
  `ReusablePaymentAddressCandidateReader`, including capability negotiation,
  prefix limits, starting height, history limits, windowing, and pagination.
- Decode real serialized Bitcoin Cash transactions, extract qualifying input
  public keys and prefixes, and preserve confirmed versus unconfirmed state.
- Make malformed responses, unsupported servers, partial windows, retry, and
  cancellation behavior explicit.

### 3. Implement The Opal Base Scan Core

- Introduce an explicit secret-bearing scan-key authority; the existing public
  `ScanKeyDescriptor` cannot perform shared-secret derivation.
- Convert each qualifying compressed input key to
  `OpalCrypto.Secp256k1.PublicKey` once per window.
- Call
  `OpalCrypto.Secp256k1.deriveSharedSecrets(privateKey:publicKeys:)` for the
  ordered window and preserve the mapping from each result to its input and
  transaction output candidates.
- Apply the selected profile's fingerprint or matching rule, derive the
  concrete BCH locking script or address, and return results with enough
  derivation and recovery metadata to restore wallet state.
- Keep secret keys and shared secrets out of diagnostics and persistence.

### 4. Add Restore Orchestration And Durable State

- Start from `WalletBirthday`, process bounded candidate windows, and handle
  confirmed history separately from the mempool.
- Deduplicate transaction hashes and outpoints, commit matches idempotently,
  and persist the last completed scan position.
- Define how partial failure, cancellation, resume, and chain reorganization
  affect the cursor and matched outputs.
- Add a concrete persistence or indexer implementation used by the product
  path. The benchmark may point it at an isolated temporary store, but it must
  execute the same serialization, indexing, and commit behavior.

### 5. Replace Structural Fixtures With A Deterministic Corpus

- Store valid serialized Bitcoin Cash transactions covering multiple inputs
  and outputs, qualifying and nonqualifying prefixes, positive and negative
  matches, duplicate candidates, window boundaries, and resume behavior.
- Use fixed test-only scan material and assert exact nonsecret outputs such as
  matched outpoints, BCH amounts in satoshis, derived locking scripts, and
  final cursor state.
- Verify batch results against the single-item primitive or vetted vectors
  before any timing sample is accepted.

### 6. Add The Release Benchmark

Only after the preceding steps pass, add an executable benchmark target that
invokes the production restore orchestrator in release mode. Use:

- workload shapes derived from actual backend limits: a small incremental
  scan, one full candidate window, and a multi-window historical restore;
- untimed fixture construction, process warmups, and repeated measured
  samples;
- separate durations for candidate loading, transaction decoding, public-key
  preparation, batch shared-secret derivation, matching and address or locking
  script work, wallet/index state mutation, persistence or indexer work, and
  total wall time;
- correctness checks before and after sampling; and
- deterministic JSON Lines output with a versioned schema, workload and count
  metadata, sample count, median and percentile durations, match count, a
  nonsecret correctness digest, and no key, shared-secret, raw transaction, or
  per-candidate material.

For each measured sample, compute:

```text
shared_secret_percentage =
    100 * shared_secret_derivation_wall_time / total_wall_time
```

Report the median sample percentage for each workload. Recommend further
OpalCrypto work only when shared-secret derivation is both the largest stage
and more than half of total wall time in the representative bulk restore
workloads. Otherwise, optimize the largest measured Opal Base stage.

## Benchmark Entry Criteria

The performance gate can open when all of the following are true:

- a selected compatibility profile and vetted vectors exist;
- a concrete candidate source returns real decodable transactions;
- production orchestration performs public-key preparation, the batch
  shared-secret call, matching, and result construction;
- restore cursor and matched-output state survive persistence and resume;
- deterministic end-to-end correctness tests pass; and
- the benchmark invokes that same orchestration with timing observation only.
