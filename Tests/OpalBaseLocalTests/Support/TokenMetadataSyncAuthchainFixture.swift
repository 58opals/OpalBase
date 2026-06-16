// TokenMetadataSyncAuthchainFixture.swift

@testable import OpalBase

struct TokenMetadataSyncAuthchainFixture: Sendable {
    let transactionReader: OpalBase.Network.TransactionReader
    let addressReader: OpalBase.Network.AddressReader
}
