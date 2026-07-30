# Cash Code v1 Candidate Profile

## Status And Terminology

This document specifies the Opal proposal for **Cash Code v1**, a compressed
P2PKH profile of Bitcoin Cash Reusable Payment Addresses (RPA).

- “Reusable Payment Address” is the technical term.
- “Cash Code” is the user-facing name and the name of this versioned profile.
- This is a candidate specification with a reference implementation and public
  deterministic vectors. It is not yet a Bitcoin Cash ecosystem standard.
- The profile becomes an interoperability claim only after an independent
  implementation consumes the same vectors and produces the same bytes.

The normative words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY describe this
candidate profile.

## Profile Boundary

Cash Code v1 supports:

- compressed secp256k1 scan, spend, sender-input, and derived payment keys;
- P2PKH payment locking bytecode;
- mainnet and the shared test-network encoding used for testnet and chipnet;
- one fixed 16-bit backend filter prefix;
- child index zero;
- expiration value zero;
- ordinary on-chain transactions; and
- CashToken-bearing outputs without changing the derivation.

Cash Code v1 does not support multisig, off-chain relay-only versions,
uncompressed sender inputs, nonzero expiration, user-selected prefix lengths,
or child indices other than zero.

The profile does not assign a mnemonic derivation path for the scan and spend
key pairs. A wallet MUST preserve the exact key origin and profile alongside
its recovery material, and MUST NOT claim that seed-only recovery is portable
between Cash Code implementations. This boundary avoids silently
reinterpreting Electron Cash paths, proposed `/2`, `/3`, or `/8` paths, or a
wallet-specific path as the same keys.

## Identifier Encoding

### Schemes, Versions, And Networks

| Expected network context | Scheme | Payload version |
| --- | --- | --- |
| mainnet | `cashcode` | `0x01` |
| testnet | `cashcodetest` | `0x05` |
| chipnet | `cashcodetest` | `0x05` |

The decoder MUST receive an expected network context. It MUST reject a
scheme/version/context mismatch. Testnet and chipnet intentionally share wire
bytes; the caller’s context preserves which network is intended.

### Application Payload

The application payload is exactly 72 bytes:

| Offset | Size | Meaning |
| --- | ---: | --- |
| 0 | 1 | network/profile version |
| 1 | 1 | prefix length in bits; exactly `0x10` |
| 2 | 33 | compressed scan public key |
| 35 | 33 | compressed spend public key |
| 68 | 4 | unsigned big-endian expiration; exactly zero |

Both public keys MUST be valid compressed secp256k1 points. The 72-byte
application payload is converted directly from eight-bit bytes to padded
five-bit values. There is no CashAddr format byte before this payload.

### Checksum

The checksum is the CashAddr polymod construction over:

```text
lower-five-bit HRP expansion
|| 0
|| padded five-bit application payload
|| eight zero five-bit values
```

The eight five-bit checksum values are appended to the payload values. The
human-readable scheme is therefore part of the checksum domain. An
implementation MUST NOT change `paycode:` to `cashcode:` without recomputing
the checksum.

A decoder MAY accept a uniformly uppercase identifier. It MUST reject mixed
case, noncanonical bit padding, an invalid checksum, an unknown scheme, an
unsupported version, or a payload length other than 72 bytes. Canonical
encoding is lowercase.

## Scan And Spend Keys

The address contains two distinct public capabilities:

- the scan public key participates in an ECDH-style shared-point operation;
- the spend public key is the parent for one non-hardened BIP32 child.

Wallets SHOULD use distinct private keys for these roles. Cash Code v1 accepts
the key pairs explicitly and does not derive them from a seed. A wallet
integrating the profile MUST preserve enough secret recovery metadata to
reproduce the same private keys and MUST bind that metadata to Cash Code v1.

## Payment Derivation

### Shared Point

For a designated sender input, the sender computes:

```text
shared_point = sender_input_private_scalar * recipient_scan_public_point
```

The receiver computes the same point as:

```text
shared_point = recipient_scan_private_scalar * sender_input_public_point
```

Take the affine x-coordinate as exactly 32-byte unsigned big-endian data,
prepend one zero byte, and hash once:

```text
shared_point_digest = SHA256(0x00 || x32)
```

Compressed SEC1 (`0x02/0x03 || x32`), uncompressed SEC1, and variable-width
x-coordinate encodings are incompatible and MUST NOT be substituted.

### Outpoint Domain

Construct the sender input outpoint text as:

```text
lowercase 64-character display-order transaction ID
|| minimal unsigned decimal output index
```

There is no separator. Hash the UTF-8/ASCII bytes once:

```text
outpoint_digest = SHA256(outpoint_text)
```

Wire-order transaction-hash bytes, uppercase hexadecimal, fixed-width decimal,
and colon-delimited text are incompatible.

### Chain Code

Interpret `shared_point_digest` and `outpoint_digest` as unsigned big-endian
integers. Add them with arbitrary precision and no curve-order reduction.
Serialize the sum as minimal unsigned big-endian bytes; a carry can produce 33
bytes. Hash once:

```text
chain_code = SHA256(minimal_be(shared_point_digest + outpoint_digest))
```

The two digests MUST NOT be treated as curve scalars, and an overflow MUST NOT
be truncated.

### Child Key

Use the 32-byte `chain_code` as the BIP32 chain code for the spend parent key.
Derive the non-hardened child at index zero:

```text
I = HMAC-SHA512(
    key: chain_code,
    data: compressed_spend_public_key || ser32_be(0)
)
```

CKDpub and CKDpriv MUST follow BIP32. Cash Code v1 fixes the index at zero, so
an invalid BIP32 tweak or point is a derivation failure rather than permission
to select a different index. The resulting payment public key is serialized
compressed.

The payment locking bytecode is exactly:

```text
OP_DUP OP_HASH160 PUSHBYTES_20
HASH160(compressed_child_public_key)
OP_EQUALVERIFY OP_CHECKSIG
```

## Qualifying Transaction Inputs

The sender MAY designate any qualifying input among the first 30 transaction
inputs. There is no additional on-chain marker identifying the designated
input, so the receiver examines each qualifying input among those positions.

A Cash Code v1 qualifying input:

- is not a coinbase input;
- spends a P2PKH output under a consensus-valid transaction;
- has the canonical two-push P2PKH unlocking-bytecode shape;
- has a structurally valid Schnorr-or-ECDSA signature plus hash-type push;
- ends with a valid 33-byte compressed secp256k1 public-key push; and
- has no trailing unlocking bytecode.

The Opal matcher consumes transactions accepted from confirmed history or a
node mempool and therefore relies on that source for full script execution.
Its local qualification pass enforces the canonical unlocking-bytecode shape
and compressed public key before any secret-bearing operation.

For each qualifying input, compute:

```text
input_digest = SHA256(SHA256(canonical_serialized_transaction_input))
```

The serialized input is the complete outpoint, CompactSize-prefixed unlocking
bytecode, and sequence. The digest MUST begin with the address filter prefix.

## Filter Prefix

Remove the compressed scan key’s first SEC1 byte and take the leading 16 bits
of its x-coordinate. Transport the value as four lowercase hexadecimal
characters.

The units are deliberately distinct:

- encoded prefix-length field: `16` bits;
- binary filter prefix: `2` bytes;
- backend request prefix: `4` hexadecimal characters.

“Four hexadecimal characters” does not mean four bytes. Cash Code v1 does not
allow the sender or recipient to configure another length.

The sender grinds a valid signature or another permitted transaction input
degree of freedom until the designated input digest has the required prefix.
Prefix grinding integration is outside the OpalBase core API; the core exposes
exact prefix derivation and matching.

## Expiration

Cash Code v1 encodes four zero bytes and has no expiration. Any nonzero
expiration is an unsupported Cash Code v1 profile.

Legacy Electron Cash interprets the same four bytes as an unsigned big-endian
Unix timestamp. A strict legacy migration parser may retain that value, but it
MUST NOT reinterpret it as a block height or silently apply it to Cash Code
v1.

## Output Matching And CashTokens

For each qualifying prefix-matching input, derive the child public key and its
exact P2PKH locking bytecode. Compare the bytes with every decoded transaction
output’s underlying locking bytecode.

A match retains:

- the transaction ID;
- qualifying input index;
- child index zero;
- transaction output index;
- the original decoded transaction output;
- the derived compressed public key; and
- an opaque receiving signing capability on the receiver path.

The original output MUST be retained without reconstructing it. In particular,
its BCH value and complete CashToken data remain unchanged. A matching
transaction output is not called a UTXO until current unspent status has been
established separately.

## Backend Contract

Cash Code v1 uses the Electrum Cash protocol 1.6 RPA methods:

```text
blockchain.rpa.get_history(prefix, from_height, to_height = -1)
blockchain.rpa.get_mempool(prefix)
```

Clients MUST respect advertised RPA capability values including
`prefix_bits_min`, `prefix_bits`, `starting_height`,
`history_block_limit`, and `max_history`. Confirmed history and mempool state
remain distinct. A server result is a candidate transaction reference, not a
payment match.

## Legacy Electron Cash Boundary

`paycode:` and `paycodetest:` identify the deployed Electron Cash profile, not
Cash Code v1. A migration parser may decode their exact 72-byte application
payload, legacy checksum domain, versions 1/5, supported prefix lengths, and
Unix-time expiration. New generation and sending MUST NOT use these schemes.

Electron Cash 4.4.5 derives an uncompressed child key before HASH160. Cash Code
v1 derives a compressed child key. The same legacy paycode and sender input
therefore produce different locking bytecode under the two profiles. A wallet
MUST NOT silently open or seed-restore an old Electron Cash RPA wallet as Cash
Code v1.

The safe legacy recovery instruction is to open the original wallet file with
Electron Cash 4.4.5 or an explicitly compatible legacy implementation, then
move funds to a newly generated wallet/profile.

## Recovery And Diagnostics

Cash Code v1 defines deterministic per-payment derivation and match metadata;
it does not define wallet persistence, consent, scheduling, or reorganization
policy. An integrating wallet owns:

- exact scan/spend key origin and secret storage;
- user authorization for scan-key use;
- network and profile binding;
- recovery start height and completed-window cursor;
- confirmed and mempool state separation;
- idempotent matched-output persistence;
- reorganization rollback; and
- migration UX.

Implementations MUST NOT log or place in general diagnostics private keys,
shared points or digests, complete Cash Codes/paycodes, filter prefixes, raw
wallet transactions, or wallet-identifying candidate material.

## Conformance Vectors

[`cash-code-v1-vectors.json`](cash-code-v1-vectors.json) and
[`cash-code-v1-negative-vectors.json`](cash-code-v1-negative-vectors.json)
are the normative public test corpus for this candidate. They include:

- exact mainnet and test-network identifiers;
- shared-point, outpoint, arbitrary-precision sum, chain-code, and BIP32
  intermediates;
- a valid Schnorr-signed Bitcoin Cash transaction whose input matches the
  fixed prefix;
- the exact compressed P2PKH locking bytecode;
- one matching CashToken-bearing output and one nonmatching output; and
- strict negative-profile material.

The transaction was reproduced independently with Electron Cash 4.4.5,
coincurve-backed secp256k1 arithmetic, and Libauth’s BCH2023 virtual machine.
The files’ SHA-256 digests are respectively
`3946e880e9869e6e162eba8e9b7ff7397bb00c6610342210d2db5d2c2bcb5ba6`
and
`e5fd12962f2065faa1bf2dd7a45e2e92a14d7704d3d2ee3a35041ca8bfff2d16`.
