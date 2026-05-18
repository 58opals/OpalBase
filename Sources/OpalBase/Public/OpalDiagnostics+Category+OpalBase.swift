// OpalDiagnostics+Category+OpalBase.swift

@preconcurrency public import OpalDiagnostics

public extension OpalDiagnostics.Category {
    static let wallet = Self(rawValue: "wallet")
    static let account = Self(rawValue: "account")
    static let addressBook = Self(rawValue: "address_book")
    static let cashFusion = Self(rawValue: "cash_fusion")
    static let transaction = Self(rawValue: "transaction")
    static let claimable = Self(rawValue: "claimable")
    static let tokenMetadata = Self(rawValue: "token_metadata")
    static let storage = Self(rawValue: "storage")

    static let all: [Self] = [
        wallet,
        account,
        addressBook,
        network,
        cashFusion,
        hedge,
        transaction,
        claimable,
        tokenMetadata,
        storage
    ]
}
