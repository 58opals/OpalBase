# OpalBase Public API Migration

This release is a semver-major public API redesign.

The package now enforces a single public namespace root: every supported public symbol lives under `OpalBase`.
Old mixed-root names are preserved only as unavailable rename shims where Swift can provide a fix-it.

## Migration rules

- Replace standalone public roots with the `OpalBase` facade namespace.
- Replace public nested `*Model` facade names with the curated role name shown below.
- Stop reaching into subordinate actors and repositories directly.
- Prefer the new forwarding APIs on `OpalBase.Wallet` and `OpalBase.Account`.

## Top-level namespace moves

| Old | New |
| --- | --- |
| `ECDSAModel` | `OpalBase.Cryptography.ECDSA` |
| `Secp256k1Model` | `OpalBase.Cryptography.Secp256k1` |
| `SchnorrModel` | `OpalBase.Cryptography.Schnorr` |
| `NonceFunctionModel` | `OpalBase.Cryptography.NoncePolicy` |
| `TokenMetadataModel` | `OpalBase.CashTokens.Metadata` |
| `TokenMetadataRepository` | `OpalBase.CashTokens.MetadataRepository` |
| `BitcoinCashMetadataRegistryClient` | `OpalBase.CashTokens.BCMR.Client` |
| `SnapshotPersistenceAdapter` | `OpalBase.Storage.SnapshotStore` |
| `SecureSecretAccessAdapter` | `OpalBase.Storage.MnemonicSecretStore` |

## Cryptography

| Old | New |
| --- | --- |
| `ECDSAModel.SignatureFormat` | `OpalBase.Cryptography.SignatureFormat` |
| `Secp256k1Model.Signature` | `OpalBase.Cryptography.Secp256k1.Signature` |
| `SchnorrModel.Signature` | `OpalBase.Cryptography.Schnorr.Signature` |
| `NonceFunctionModel.ECDSA` | `OpalBase.Cryptography.NoncePolicy.ECDSA` |

Use `OpalBase.Cryptography.Secp256k1.Operation` for public key derivation and tweak operations.

## CashTokens

| Old | New |
| --- | --- |
| `OpalBase.CashTokens.CategoryIDModel` | `OpalBase.CashTokens.CategoryID` |
| `OpalBase.CashTokens.NFTModel` | `OpalBase.CashTokens.NFT` |
| `OpalBase.CashTokens.TokenPrefixModel` | `OpalBase.CashTokens.TokenPrefix` |
| `OpalBase.CashTokens.MetadataRepository.SnapshotModel` | `OpalBase.CashTokens.MetadataRepository.Snapshot` |
| `BitcoinCashMetadataRegistryClient.AuthchainResolverModel` | `OpalBase.CashTokens.BCMR.Client.AuthchainResolver` |
| `BitcoinCashMetadataRegistryClient.ChainResolvedRegistryModel` | `OpalBase.CashTokens.BCMR.Client.ChainResolvedRegistry` |
| `BitcoinCashMetadataRegistryClient.FetcherModel` | `OpalBase.CashTokens.BCMR.Client.Fetcher` |
| `BitcoinCashMetadataRegistryClient.IdentitySnapshotModel` | `OpalBase.CashTokens.BCMR.Client.IdentitySnapshot` |
| `BitcoinCashMetadataRegistryClient.PublicationModel` | `OpalBase.CashTokens.BCMR.Client.Publication` |
| `BitcoinCashMetadataRegistryClient.RegistryModel` | `OpalBase.CashTokens.BCMR.Client.Registry` |
| `BitcoinCashMetadataRegistryClient.TokenSnapshotModel` | `OpalBase.CashTokens.BCMR.Client.TokenSnapshot` |

Wallet metadata APIs now stay on the wallet facade:

- `await wallet.fetchTokenMetadata(for:)`
- `await wallet.upsertTokenMetadata(_:)`
- `await wallet.makeTokenMetadataSnapshot()`
- `await wallet.applyTokenMetadataSnapshot(_:)`

## Storage

| Old | New |
| --- | --- |
| `OpalBase.Storage.PortsModel` | `OpalBase.Storage.Ports` |
| `OpalBase.Storage.PersistenceSessionModel` | `OpalBase.Storage.PersistenceSession` |
| `OpalBase.Storage.SecurityModel` | `OpalBase.Storage.Security` |
| `OpalBase.Storage.KeyModel` | `OpalBase.Storage.Key` |
| `OpalBase.Storage.ValueRepository` | `OpalBase.Storage.ValueStore` |

Protocol-oriented storage customization now uses:

- `OpalBase.Storage.SnapshotStore`
- `OpalBase.Storage.MnemonicSecretStore`
- `OpalBase.Storage.Ports`
- `OpalBase.Storage.PersistenceSession`

## Block

| Old | New |
| --- | --- |
| `OpalBase.Block.HeaderModel` | `OpalBase.Block.Header` |

`OpalBase.Block.Header.calculateTarget(for:)` now returns `OpalBase.Block.Target`.

`LargeUnsignedIntegerModel` is no longer part of the public surface.

## Curated nested renames

| Old | New |
| --- | --- |
| `OpalBase.Address.FormatModel` | `OpalBase.Address.Format` |
| `OpalBase.Address.Book.CoinSelectionModel` | `OpalBase.Address.Book.CoinSelection` |
| `OpalBase.Address.Book.EntryModel` | `OpalBase.Address.Book.Entry` |
| `OpalBase.Address.Book.SnapshotModel` | `OpalBase.Address.Book.Snapshot` |
| `OpalBase.Address.Book.TokenInventoryModel` | `OpalBase.Address.Book.TokenInventory` |
| `OpalBase.Address.Book.UTXOChangeSetModel` | `OpalBase.Address.Book.UTXOChangeSet` |
| `OpalBase.Address.Book.UTXORefreshModel` | `OpalBase.Address.Book.UTXORefresh` |
| `OpalBase.Address.Book.UnspentOutputBalancesModel` | `OpalBase.Address.Book.UnspentOutputBalances` |
| `OpalBase.Address.Book.UnspentOutputPartitionModel` | `OpalBase.Address.Book.UnspentOutputPartition` |
| `OpalBase.Address.Book.UsageScanModel` | `OpalBase.Address.Book.UsageScan` |
| `OpalBase.Account.ReservedSupplyModel` | `OpalBase.Account.ReservedSupply` |
| `OpalBase.Account.SnapshotModel` | `OpalBase.Account.Snapshot` |
| `OpalBase.DerivationPath.CoinTypeModel` | `OpalBase.DerivationPath.CoinType` |
| `OpalBase.DerivationPath.PurposeModel` | `OpalBase.DerivationPath.Purpose` |
| `OpalBase.DerivationPath.UsageModel` | `OpalBase.DerivationPath.Usage` |
| `OpalBase.Mnemonic.LengthModel` | `OpalBase.Mnemonic.Length` |
| `OpalBase.Mnemonic.WordModel` | `OpalBase.Mnemonic.Word` |
| `OpalBase.Mnemonic.WordListModel` | `OpalBase.Mnemonic.WordList` |
| `OpalBase.PrivateKey.WalletImportFormatCompressionModel` | `OpalBase.PrivateKey.WalletImportFormatCompression` |
| `OpalBase.PublicKey.HashModel` | `OpalBase.PublicKey.Hash` |
| `OpalBase.Network.DiagnosticsSnapshotModel` | `OpalBase.Network.DiagnosticsSnapshot` |
| `OpalBase.Network.DiagnosticsSubscriptionModel` | `OpalBase.Network.DiagnosticsSubscription` |
| `OpalBase.Network.EnvironmentModel` | `OpalBase.Network.Environment` |
| `OpalBase.Network.FulcrumRequestTimeoutModel` | `OpalBase.Network.FulcrumRequestTimeout` |
| `OpalBase.Network.FulcrumScriptHashReaderModel` | `OpalBase.Network.FulcrumScriptHashReader` |
| `OpalBase.Network.FulcrumTransactionProofReaderModel` | `OpalBase.Network.FulcrumTransactionProofReader` |
| `OpalBase.Network.FulcrumTransactionReaderModel` | `OpalBase.Network.FulcrumTransactionReader` |
| `OpalBase.Network.LogLevelModel` | `OpalBase.Network.LogLevel` |
| `OpalBase.Network.MempoolFeeHistogramBinModel` | `OpalBase.Network.MempoolFeeHistogramBin` |
| `OpalBase.Network.MempoolInfoModel` | `OpalBase.Network.MempoolInfo` |
| `OpalBase.Network.ServerCatalogModel` | `OpalBase.Network.ServerCatalog` |
| `OpalBase.Network.TransactionPositionResolutionModel` | `OpalBase.Network.TransactionPositionResolution` |
| `OpalBase.Transaction.DetailedModel` | `OpalBase.Transaction.Detail` |
| `OpalBase.Transaction.HashModel` | `OpalBase.Transaction.Hash` |
| `OpalBase.Transaction.HashTypeModel` | `OpalBase.Transaction.HashType` |
| `OpalBase.Transaction.HistoryModel` | `OpalBase.Transaction.History` |
| `OpalBase.Transaction.InputModel` | `OpalBase.Transaction.Input` |
| `OpalBase.Transaction.OutputModel` | `OpalBase.Transaction.Output` |
| `OpalBase.Transaction.OutputOrderingStrategyModel` | `OpalBase.Transaction.OutputOrderingStrategy` |
| `OpalBase.Transaction.SimpleModel` | `OpalBase.Transaction.Summary` |
| `OpalBase.Transaction.UnlockerModel` | `OpalBase.Transaction.Unlocker` |

## Removed direct subordinate access

These members are no longer public:

- `OpalBase.Wallet.tokenMetadataStore`
- `OpalBase.Account.addressBook`

Use the facade forwarding APIs instead:

- Wallet metadata: `fetchTokenMetadata`, `upsertTokenMetadata`, `makeTokenMetadataSnapshot`, `applyTokenMetadataSnapshot`
- Account balances/history: `loadBalanceFromCache`, `loadTransactionHistory`
- Account address management: `listEntries`, `selectNextEntry`, `readGapLimit`
- Account token inventory: `loadTokenInventory`

## Migration workflow

1. Replace old type names using compiler fix-its from the unavailable shims.
2. Move any direct `tokenMetadataStore` or `addressBook` access to the new forwarding APIs.
3. Replace any use of compact target integers with `OpalBase.Block.Target`.
4. Run your package build and tests after each subsystem rename because many of these names appear in generic signatures and nested types.
