# RPA Compatibility Decision

## Outcome

OpalBase selects the profile in
[`cash-code-v1.md`](cash-code-v1.md) as a proposed, versioned Cash Code v1
candidate and reference implementation.

This is an intentional standardization proposal, not a claim that the profile
is already a Bitcoin Cash standard. The scheme change, strict decoder, fixed
compressed-key behavior, and independent vectors prevent the proposal from
silently changing the meaning of deployed Electron Cash `paycode:` values.

## Compatibility Matrix

| Concern | Legacy Electron Cash 4.4.5 | Cash Code v1 candidate |
| --- | --- | --- |
| User-facing scheme | `paycode:` / `paycodetest:` | `cashcode:` / `cashcodetest:` |
| Opal behavior | Strict read-only migration parse | Generate, parse, derive, and match |
| Payload | 72 application bytes, no CashAddr format byte | Same byte layout, strict exact length |
| Checksum | HRP-bound RPA/CashAddr polymod | Same construction with the new HRP |
| Version/network | Generated v1 mainnet, v5 test networks; historical parser is loose | v1 mainnet and v5 expected test context; strict scheme/version/context binding |
| Scan/spend fields | Compressed public keys | Compressed public keys |
| Scan/spend seed path | Legacy wallet-relative `/0/0` and `/0/1` | Not assigned; explicit key pairs and exact wallet-owned recovery origin |
| Shared point digest | `SHA256(00 || x32)` | Preserved byte-for-byte |
| Outpoint domain | Display-order lowercase txid text plus minimal decimal vout, no delimiter | Preserved byte-for-byte |
| Integer construction | Arbitrary-precision unsigned sum, minimal big-endian, no modulus | Preserved byte-for-byte |
| Child derivation | Non-hardened BIP32; deployed index zero | Non-hardened BIP32 index zero only |
| Output key | Uncompressed child before HASH160 | Compressed child before HASH160 |
| Sender inputs | Electron Cash accepts compressed or uncompressed P2PKH-style keys | Canonical compressed P2PKH only, first 30 inputs |
| Prefix | Generated as 16 bits; parser/sender accept exactly 4, 8, 12, or 16 bits | Fixed 16 bits = 2 bytes = 4 hex characters |
| Expiration | Unsigned big-endian Unix time; generation writes zero | Zero only |
| CashTokens | Predates CashTokens | Match the underlying locking bytecode and retain the original token-aware output |
| Recovery | Old wallet file and legacy key path | Explicit profile/key-origin binding; no silent seed reinterpretation |

## Evidence And Intentional Corrections

The byte contract was derived from:

- the [Reusable Address Proposal](https://github.com/imaginaryusername/Reusable_specs/blob/16025c2f9f20c9dd16e1619a7a742dad908865f3/reusable_addresses.md);
- [Electron Cash 4.4.5](https://github.com/Electron-Cash/Electron-Cash/tree/019181450664f7031008c53e9999ab8892ad57e3/electroncash/rpa);
- current Electron Cash RPA source and tests;
- [Electron Cash PR 3225](https://github.com/Electron-Cash/Electron-Cash/pull/3225) and [PR 3226](https://github.com/Electron-Cash/Electron-Cash/pull/3226);
- Fulcrum’s RPA index and the
  [Electrum Cash protocol 1.6 methods](https://electrum-cash-protocol.readthedocs.io/en/latest/protocol-methods.html);
- the Selene and Fyookball TypeScript implementations; and
- the [Cash Code naming discussion](https://bitcoincashresearch.org/t/cash-code-as-a-user-facing-name-for-rpa/1917).

The implementation gate was closed against these immutable revisions:

| Component | Reviewed revision |
| --- | --- |
| Reusable Address Proposal | [`16025c2f9f20c9dd16e1619a7a742dad908865f3`](https://github.com/imaginaryusername/Reusable_specs/blob/16025c2f9f20c9dd16e1619a7a742dad908865f3/reusable_addresses.md) |
| Electron Cash 4.4.5 | [`019181450664f7031008c53e9999ab8892ad57e3`](https://github.com/Electron-Cash/Electron-Cash/tree/019181450664f7031008c53e9999ab8892ad57e3/electroncash/rpa) |
| Electron Cash current source reviewed 2026-07-30 | [`4487003a4c51c0e5e2983147c1541cc5b3192a2b`](https://github.com/Electron-Cash/Electron-Cash/tree/4487003a4c51c0e5e2983147c1541cc5b3192a2b/electroncash/rpa) |
| OpalCrypto hardened shared-point and explicit-child APIs | [`d698e2809d0bc1a52a4227a0315392916e29c307`](https://github.com/58opals/OpalCrypto/commit/d698e2809d0bc1a52a4227a0315392916e29c307) |
| SwiftFulcrum typed RPA transport | [`66a5a8ba9381b21881ad074d3a8dec3dc473ba0f`](https://github.com/58opals/SwiftFulcrum/commit/66a5a8ba9381b21881ad074d3a8dec3dc473ba0f) |

Current Electron Cash master retains the 4.4.5 RPA derivation behavior. PR 3225
is a breaking compressed-output proposal, and PR 3226 changes wallet
organization and derivation paths without defining portable seed recovery.
Neither change can be applied invisibly to existing paycodes.

Cash Code v1 deliberately corrects the experimental surface by:

1. changing the checksum-bound scheme;
2. enforcing a profile/network version at parse time;
3. fixing compressed sender and payment keys;
4. fixing prefix length and expiration;
5. rejecting legacy generation and matching; and
6. returning token-aware decoded outputs rather than reconstructed values.

The candidate retains the legacy bytes that independent implementations agree
on: shared-point x serialization, outpoint text, arbitrary-precision sum, and
BIP32 child derivation.

## Encoding Conflict

RPA encoding is not simply “CashAddr for a longer payload.” The 72-byte
application payload is converted directly to five-bit symbols. Selene’s use of
a generic CashAddr encoder inserts an extra format byte and produces a
different identifier.

The strict decoder rejects that 73-byte framing. It also rejects mixed case,
bad or cross-scheme checksums, noncanonical padding, unknown versions,
unsupported prefix lengths, nonzero Cash Code expiration, invalid public
keys, and scheme/network mismatches.

## Compression And Legacy Safety

The public vector’s child point produces:

- legacy uncompressed P2PKH locking bytecode
  `76a914798950219659e8753a0e82b0b67435516bd5534788ac`; and
- Cash Code v1 compressed P2PKH locking bytecode
  `76a9143d61c96622930aa8890653535c41c359677d4fed88ac`.

This difference can make a payment undiscoverable by the intended wallet if an
unversioned paycode is reinterpreted. OpalBase therefore parses a legacy
paycode only as `.legacyElectronCash`, refuses to encode it, and refuses to use
it for Cash Code v1 payment derivation or matching.

## Prefix Units

Fulcrum, Electron Cash, and the working TypeScript derivations use the leading
double-SHA-256 hexadecimal characters. For the independent Fulcrum input
vector, the digest begins `ddd6`, so the 16-bit query is `ddd6`.

Electron Cash stores the bit count in one payload byte and maps the accepted
values 4, 8, 12, and 16 to 1, 2, 3, and 4 hexadecimal characters. Its wallet
generation path writes 16 bits. It does not define a four-byte generated
prefix.

Cash Code v1 fixes the generated value as:

```text
16 bits = 2 binary bytes = 4 hexadecimal characters
```

The payload field is `0x10`. Describing this as “four bytes” is incompatible
with both the encoded field and backend request.

## Input And Backend Semantics

Fulcrum indexes candidate serialized inputs; it does not establish an RPA
payment. OpalBase must:

1. keep confirmed history and mempool references distinct;
2. fetch and exactly decode the referenced transaction;
3. inspect at most the first 30 inputs;
4. require canonical compressed P2PKH unlocking-bytecode shape;
5. verify the full serialized-input prefix;
6. derive the compressed child key; and
7. compare exact output locking bytecode.

The concrete SwiftFulcrum handoff adds typed protocol 1.6 history and mempool
requests with capability and limit validation. It does not add historical
restore orchestration.

The completed dependency contracts are deliberately narrow:

- OpalCrypto exposes
  `Secp256k1.deriveSharedPointXCoordinate(signingKey:publicKey:)`,
  `Key.deriveNonHardenedChildPublicKey(from:chainCode:at:)`, and
  `Key.deriveNonHardenedChildSigningKey(from:chainCode:at:)`. The receiving
  private child remains an opaque signing capability.
- SwiftFulcrum exposes
  `API.blockchain.rpa.history(prefix:fromHeight:toHeight:)` and
  `API.blockchain.rpa.mempool(prefix:)` with typed response transactions.
  Protocol negotiation and advertised RPA capability validation remain owned
  by SwiftFulcrum.

Neither dependency owns Cash Code profile policy, wallet recovery, persistence,
or background scheduling.

## Recovery Boundary

No reviewed protocol source defines a portable seed path, durable scan cursor,
idempotent match repository, or chain-reorganization contract. Cash Code v1
therefore makes the absence explicit:

- scan and spend signing capabilities are supplied to OpalBase;
- a match contains exact input/output/child metadata and an opaque receiving
  signing capability;
- Wallet owns key-origin persistence, consent, scheduling, migration UX, and
  app lifecycle; and
- seed-only recovery MUST NOT be advertised as portable.

Legacy Electron Cash recovery remains an explicit migration workflow using the
old wallet file and a compatible legacy implementation. OpalBase does not
pretend that a new Cash Code wallet can recover those outputs from the old
seed under a new path or compression mode.

## Remaining Standardization Gate

The Opal implementation and independent vector reproduction establish a
candidate contract. The remaining external standardization prerequisite is a
second implementation that consumes
[`cash-code-v1-vectors.json`](cash-code-v1-vectors.json) and
[`cash-code-v1-negative-vectors.json`](cash-code-v1-negative-vectors.json),
and agrees on the encoded identifiers, child keys, raw transaction match, and
negative cases.

Until that occurs, documentation and public communication must call Cash Code
v1 a proposal or candidate, not an ecosystem standard.
