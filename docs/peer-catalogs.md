# Peer catalog snapshot

OpalBase maintains its own default Fulcrum URL lists. They are first-party-maintained configuration for community services, not an automatically synchronized copy of SwiftFulcrum's bundled resources. **Every endpoint below is not live-qualified by this snapshot.** Historical upstream import provenance, independently established operator identity and independence, and last live qualification are not recorded.

The authoritative shared review and qualification contract is [SwiftFulcrum's peer catalog contract](https://github.com/58opals/SwiftFulcrum/blob/develop/docs/peer-catalogs.md). It defines the distinction between source integrity, live observations, operator evidence and application trust. OpalBase's distinct source inventory and integration semantics are recorded here.

## Source evidence

Offline review on 2026-10-27 recorded [ServerCatalog.swift](../Sources/OpalBase/Network/OpalBase+Network+ServerCatalog.swift) at public integration revision `7303d53cf1758f5a685d1dc42d0e747071b45dd8`. The containing source file has SHA-256 `f4797dea6e5fb0bd558932df001d3742a878041ac9a9011d8572cf77951a84e1`; its latest recorded file change is `407976a386236c1a35801b83b8d88cea84dcc58a` (2026-07-03). This binds current repository bytes, not a historical upstream source, a peer operator or a successful connection. No live qualification was performed for this snapshot.

| Network | Position | Default endpoint |
| --- | --- | --- |
| mainnet | 1 | `wss://bch.imaginary.cash:50004` |
| mainnet | 2 | `wss://bch.loping.net:50004` |
| mainnet | 3 | `wss://fulcrum.greyh.at:50004` |
| mainnet | 4 | `wss://cashnode.bch.ninja:50004` |
| mainnet | 5 | `wss://electrum.imaginary.cash:50004` |
| mainnet | 6 | `wss://electroncash.dk:50004` |
| testnet | 1 | `wss://testnet.imaginary.cash:50004` |
| testnet | 2 | `wss://testnet.bch.loping.net:51004` |
| chipnet | 1 | `wss://chipnet.imaginary.cash:50004` |

These are stored-order inventories, not health rankings or operator-diversity claims. The existing Base mainnet list omits the fountainhead.cash and jettscythe.xyz entries retained by SwiftFulcrum. This snapshot preserves that difference without asserting a current reason or health verdict.

## Integration semantics

Nonempty `Network.Configuration.serverURLs` remain authoritative primary URLs; otherwise Base selects its catalog for the configured environment. Its regular repository checks the requested network, appends supplied fallback URLs and normalizes/deduplicates the combined list while preserving first occurrence. The separate exact-endpoint repository ignores provider fallback catalogs. See the [configuration adapter](../Sources/OpalBase/Network/OpalBase+Network+Configuration+Fulcrum.swift).

The default lists use `wss`; existing support for custom URLs, scheme normalization, URL filtering and TLS behavior is unchanged. A configured or connected provider is not evidence of canonical-chain completeness or honest account data. Applications retain their provider and chain-view verification responsibilities.

Before changing a default, follow SwiftFulcrum's linked contract, review the ordered URL diff and refresh this source snapshot. Run `sh scripts/validate.sh focused NetworkServerCatalogValidator` for the offline inventory, network mapping, override, fallback and normalization contracts. Exact ordered expectations guard against unreviewed default-peer changes; their passing result does not establish reachability, operators, balances, transaction-history completeness or full-node readiness.
