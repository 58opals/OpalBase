// OpalBase+Migration.swift

import Foundation

@available(*, unavailable, renamed: "OpalBase.Cryptography.ECDSA")
public typealias ECDSAModel = OpalBase.Cryptography.ECDSA

@available(*, unavailable, renamed: "OpalBase.Cryptography.Secp256k1")
public typealias Secp256k1Model = OpalBase.Cryptography.Secp256k1

@available(*, unavailable, renamed: "OpalBase.Cryptography.Schnorr")
public typealias SchnorrModel = OpalBase.Cryptography.Schnorr

@available(*, unavailable, renamed: "OpalBase.Cryptography.NoncePolicy")
public typealias NonceFunctionModel = OpalBase.Cryptography.NoncePolicy

@available(*, unavailable, renamed: "OpalBase.CashTokens.Metadata")
public typealias TokenMetadataModel = OpalBase.CashTokens.Metadata

@available(*, unavailable, renamed: "OpalBase.CashTokens.MetadataRepository")
public typealias TokenMetadataRepository = OpalBase.CashTokens.MetadataRepository

@available(*, unavailable, renamed: "OpalBase.CashTokens.BCMR.Client")
public typealias BitcoinCashMetadataRegistryClient = OpalBase.CashTokens.BCMR.Client

@available(*, unavailable, renamed: "OpalBase.Storage.SnapshotStore")
public typealias SnapshotPersistenceAdapter = OpalBase.Storage.SnapshotStore

@available(*, unavailable, renamed: "OpalBase.Storage.MnemonicSecretStore")
public typealias SecureSecretAccessAdapter = OpalBase.Storage.MnemonicSecretStore

extension _OpalBase.Block {
    @available(*, unavailable, renamed: "Header")
    public typealias HeaderModel = Header
}

extension _OpalBase.Account {
    @available(*, unavailable, renamed: "ReservedSupply")
    public typealias ReservedSupplyModel = ReservedSupply

    @available(*, unavailable, renamed: "Snapshot")
    public typealias SnapshotModel = Snapshot
}

extension _OpalBase.Address {
    @available(*, unavailable, renamed: "Format")
    public typealias FormatModel = Format
}

extension _OpalBase.Address.Book {
    @available(*, unavailable, renamed: "CoinSelection")
    public typealias CoinSelectionModel = CoinSelection

    @available(*, unavailable, renamed: "Entry")
    public typealias EntryModel = Entry

    @available(*, unavailable, renamed: "Snapshot")
    public typealias SnapshotModel = Snapshot

    @available(*, unavailable, renamed: "TokenInventory")
    public typealias TokenInventoryModel = TokenInventory

    @available(*, unavailable, renamed: "UTXOChangeSet")
    public typealias UTXOChangeSetModel = UTXOChangeSet

    @available(*, unavailable, renamed: "UTXORefresh")
    public typealias UTXORefreshModel = UTXORefresh

    @available(*, unavailable, renamed: "UnspentOutputBalances")
    public typealias UnspentOutputBalancesModel = UnspentOutputBalances

    @available(*, unavailable, renamed: "UnspentOutputPartition")
    public typealias UnspentOutputPartitionModel = UnspentOutputPartition

    @available(*, unavailable, renamed: "UsageScan")
    public typealias UsageScanModel = UsageScan
}

extension _OpalBase.CashTokens {
    @available(*, unavailable, renamed: "CategoryID")
    public typealias CategoryIDModel = CategoryID

    @available(*, unavailable, renamed: "NFT")
    public typealias NFTModel = NFT

    @available(*, unavailable, renamed: "TokenPrefix")
    public typealias TokenPrefixModel = TokenPrefix
}

extension _OpalBase.CashTokens.MetadataRepository {
    @available(*, unavailable, renamed: "Snapshot")
    public typealias SnapshotModel = Snapshot
}

extension _OpalBase.CashTokens.BCMR.Client {
    @available(*, unavailable, renamed: "AuthchainResolver")
    public typealias AuthchainResolverModel = AuthchainResolver

    @available(*, unavailable, renamed: "ChainResolvedRegistry")
    public typealias ChainResolvedRegistryModel = ChainResolvedRegistry

    @available(*, unavailable, renamed: "Fetcher")
    public typealias FetcherModel = Fetcher

    @available(*, unavailable, renamed: "IdentitySnapshot")
    public typealias IdentitySnapshotModel = IdentitySnapshot

    @available(*, unavailable, renamed: "Publication")
    public typealias PublicationModel = Publication

    @available(*, unavailable, renamed: "Registry")
    public typealias RegistryModel = Registry

    @available(*, unavailable, renamed: "TokenSnapshot")
    public typealias TokenSnapshotModel = TokenSnapshot
}

extension _OpalBase.Cryptography.ECDSA {
    @available(*, unavailable, renamed: "OpalBase.Cryptography.SignatureFormat")
    public typealias SignatureFormat = OpalBase.Cryptography.SignatureFormat
}

extension _OpalBase.DerivationPath {
    @available(*, unavailable, renamed: "CoinType")
    public typealias CoinTypeModel = CoinType

    @available(*, unavailable, renamed: "Purpose")
    public typealias PurposeModel = Purpose

    @available(*, unavailable, renamed: "Usage")
    public typealias UsageModel = Usage
}

extension _OpalBase.Mnemonic {
    @available(*, unavailable, renamed: "Length")
    public typealias LengthModel = Length

    @available(*, unavailable, renamed: "Word")
    public typealias WordModel = Word

    @available(*, unavailable, renamed: "WordList")
    public typealias WordListModel = WordList
}

extension _OpalBase.PrivateKey {
    @available(*, unavailable, renamed: "WalletImportFormatCompression")
    public typealias WalletImportFormatCompressionModel = WalletImportFormatCompression
}

extension _OpalBase.PublicKey {
    @available(*, unavailable, renamed: "Hash")
    public typealias HashModel = Hash
}

extension _OpalBase.Network {
    @available(*, unavailable, renamed: "DiagnosticsSnapshot")
    public typealias DiagnosticsSnapshotModel = DiagnosticsSnapshot

    @available(*, unavailable, renamed: "DiagnosticsSubscription")
    public typealias DiagnosticsSubscriptionModel = DiagnosticsSubscription

    @available(*, unavailable, renamed: "Environment")
    public typealias EnvironmentModel = Environment

    @available(*, unavailable, renamed: "FulcrumRequestTimeout")
    public typealias FulcrumRequestTimeoutModel = FulcrumRequestTimeout

    @available(*, unavailable, renamed: "FulcrumScriptHashReader")
    public typealias FulcrumScriptHashReaderModel = FulcrumScriptHashReader

    @available(*, unavailable, renamed: "FulcrumTransactionProofReader")
    public typealias FulcrumTransactionProofReaderModel = FulcrumTransactionProofReader

    @available(*, unavailable, renamed: "FulcrumTransactionReader")
    public typealias FulcrumTransactionReaderModel = FulcrumTransactionReader

    @available(*, unavailable, renamed: "LogLevel")
    public typealias LogLevelModel = LogLevel

    @available(*, unavailable, renamed: "MempoolFeeHistogramBin")
    public typealias MempoolFeeHistogramBinModel = MempoolFeeHistogramBin

    @available(*, unavailable, renamed: "MempoolInfo")
    public typealias MempoolInfoModel = MempoolInfo

    @available(*, unavailable, renamed: "ServerCatalog")
    public typealias ServerCatalogModel = ServerCatalog

    @available(*, unavailable, renamed: "TransactionPositionResolution")
    public typealias TransactionPositionResolutionModel = TransactionPositionResolution
}

extension _OpalBase.Storage {
    @available(*, unavailable, renamed: "Key")
    public typealias KeyModel = Key

    @available(*, unavailable, renamed: "PersistenceSession")
    public typealias PersistenceSessionModel = PersistenceSession

    @available(*, unavailable, renamed: "Ports")
    public typealias PortsModel = Ports

    @available(*, unavailable, renamed: "Security")
    public typealias SecurityModel = Security

    @available(*, unavailable, renamed: "ValueStore")
    public typealias ValueRepository = ValueStore
}

extension _OpalBase.Transaction {
    @available(*, unavailable, renamed: "Detail")
    public typealias DetailedModel = Detail

    @available(*, unavailable, renamed: "Hash")
    public typealias HashModel = Hash

    @available(*, unavailable, renamed: "HashType")
    public typealias HashTypeModel = HashType

    @available(*, unavailable, renamed: "History")
    public typealias HistoryModel = History

    @available(*, unavailable, renamed: "Input")
    public typealias InputModel = Input

    @available(*, unavailable, renamed: "Output")
    public typealias OutputModel = Output

    @available(*, unavailable, renamed: "OutputOrderingStrategy")
    public typealias OutputOrderingStrategyModel = OutputOrderingStrategy

    @available(*, unavailable, renamed: "Summary")
    public typealias SimpleModel = Summary

    @available(*, unavailable, renamed: "Unlocker")
    public typealias UnlockerModel = Unlocker
}
