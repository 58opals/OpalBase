// TokenMetadataSyncAuthchainFixture.swift

@testable import OpalBase
@testable import OpalBaseCore

struct TokenMetadataSyncAuthchainFixture: Sendable {
    let transactionReader: OpalBase.Network.TransactionReader
    let addressReader: OpalBase.Network.AddressReader
}
