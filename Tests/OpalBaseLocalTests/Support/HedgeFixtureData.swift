// HedgeFixtureData.swift

import Foundation
import OpalCrypto
@testable import OpalBase

enum HedgeFixtureData {
    static let oraclePublicKeyHex = "029174c105b4d7be73b0e25b3b204dfab054bd2c12f7d7e38a5de4f4d05decc58f"
    static let startingOracleMessageHex = "db6409000100000001000000305c0000"
    static let startingOracleSignatureHex =
        "a8744a655a03107fb3b8e46eaee5519899960f258726d4fa6a74b6cbeb9a62ef" +
        "e96e012233cfbefc44378b820eb76bc4ef11e196ae5d47116ed9cbad93c6a818"
    static let shortPayoutAddress = "bitcoincash:qq59hv6s3qdjrtyfwfxxldkuj9xsjmx48vrz882knz"
    static let longPayoutAddress = "bitcoincash:qpzlruwy4xu5rxjs3z37nsj29y7h59gwvsu4ddp0u4"
    static let shortLockScriptHex = "76a914285bb350881b21ac89724c6fb6dc914d096cd53b88ac"
    static let longLockScriptHex = "76a91445f1f1c4a9b9419a5088a3e9c24a293d7a150e6488ac"
    static let shortMutualRedeemPublicKeyHex =
        "020797d8fd4d2fa6fd7cdeabe2526bfea2b90525d6e8ad506ec4ee3c53885aa309"
    static let longMutualRedeemPublicKeyHex =
        "028a53f95eb631b460854fc836b2e5d31cad16364b4dc3d970babfbdcc3f2e4954"

    static let expectedFundingAddress = "bitcoincash:ppk0waq58v6sgc2g4y8nlypykt7ev4q7tsa5nzzwvx"
    static let expectedFundingSatoshis: UInt64 = 5_651_049
    static let expectedPayoutSatoshis: UInt64 = 5_649_717
    static let expectedHedgePayoutSatoshis: UInt64 = 4_255_319
    static let expectedLongPayoutSatoshis: UInt64 = 1_394_398
    static let expectedSettlementPrice: Int64 = 23_500
    static let startingTimestamp: Int64 = 615_643
    static let fixtureMaturityTimestamp: Int64 = 6_663_643

    static let fundingTransactionHashHex = String(repeating: "1", count: 64)
    static let settlementTransactionHashHex = String(repeating: "2", count: 64)

    static var fundingTransactionHash: OpalBase.Transaction.Hash {
        try! OpalBase.Hedge.transactionHash(fromExternalHex: fundingTransactionHashHex)
    }

    static var settlementTransactionHash: OpalBase.Transaction.Hash {
        try! OpalBase.Hedge.transactionHash(fromExternalHex: settlementTransactionHashHex)
    }

    static func startingOracleProof() -> OpalBase.Hedge.OracleProofInput {
        .init(
            messageHex: startingOracleMessageHex,
            signatureHex: startingOracleSignatureHex,
            publicKeyHex: oraclePublicKeyHex
        )
    }

    static func shortParticipant(
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> OpalBase.Hedge.ParticipantMaterial {
        try participant(
            side: .hedge,
            addressString: shortPayoutAddress,
            lockingScriptHex: shortLockScriptHex,
            mutualRedeemPublicKeyHex: shortMutualRedeemPublicKeyHex,
            network: network
        )
    }

    static func longParticipant(
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> OpalBase.Hedge.ParticipantMaterial {
        try participant(
            side: .long,
            addressString: longPayoutAddress,
            lockingScriptHex: longLockScriptHex,
            mutualRedeemPublicKeyHex: longMutualRedeemPublicKeyHex,
            network: network
        )
    }

    static func betaRequest(
        walletParticipant: OpalBase.Hedge.ParticipantMaterial? = nil,
        counterpartyParticipant: OpalBase.Hedge.ParticipantMaterial? = nil,
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest {
        try OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest(
            walletParticipant: walletParticipant ?? shortParticipant(network: network),
            counterpartyParticipant: counterpartyParticipant ?? longParticipant(network: network),
            startingOracleProof: startingOracleProof(),
            nominalUnits: 1_000,
            maturityTimestamp: fixtureMaturityTimestamp,
            network: network
        )
    }

    static func signedBetaRequest(
        walletParticipant: OpalBase.Hedge.ParticipantMaterial? = nil,
        counterpartyParticipant: OpalBase.Hedge.ParticipantMaterial? = nil,
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest {
        try OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest(
            walletParticipant: walletParticipant ?? shortParticipant(network: network),
            counterpartyParticipant: counterpartyParticipant ?? longParticipant(network: network),
            startingOracleProof: signedOracleProof(
                messageTimestamp: startingTimestamp,
                messageSequence: 1,
                priceSequence: 1,
                priceValue: 23_600
            ),
            nominalUnits: 1_000,
            maturityTimestamp: fixtureMaturityTimestamp,
            network: network
        )
    }

    static func signedSettlementOracleProof() throws -> OpalBase.Hedge.OracleProofInput {
        try signedOracleProof(
            messageTimestamp: fixtureMaturityTimestamp,
            messageSequence: 2,
            priceSequence: 2,
            priceValue: expectedSettlementPrice
        )
    }

    private static func participant(
        side: OpalBase.Hedge.Side,
        addressString: String,
        lockingScriptHex: String,
        mutualRedeemPublicKeyHex: String,
        network: OpalBase.Network.Environment
    ) throws -> OpalBase.Hedge.ParticipantMaterial {
        let sourceAddress = try OpalBase.Address(string: addressString, network: .mainnet)
        let payoutAddress = try OpalBase.Address(
            script: sourceAddress.lockingScript,
            network: network
        )
        return OpalBase.Hedge.ParticipantMaterial(
            side: side,
            payoutAddress: payoutAddress,
            lockingScriptHex: lockingScriptHex,
            mutualRedeemPublicKeyHex: mutualRedeemPublicKeyHex
        )
    }

    private static func signedOracleProof(
        messageTimestamp: Int64,
        messageSequence: Int64,
        priceSequence: Int64,
        priceValue: Int64
    ) throws -> OpalBase.Hedge.OracleProofInput {
        let messageHex = makeOracleMessageHex(
            messageTimestamp: messageTimestamp,
            messageSequence: messageSequence,
            priceSequence: priceSequence,
            priceValue: priceValue
        )
        let messageData = try Data(hexadecimalString: messageHex)
        let privateKey = try OpalCrypto.Secp256k1.PrivateKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([0x01])
        )
        let publicKey = try OpalCrypto.Signature.deriveVerificationKey(
            from: privateKey
        )
        let digest = try OpalCrypto.Signature.Digest(
            rawRepresentation: OpalCrypto.Hashing.sha256(messageData)
        )
        let signature = try OpalCrypto.Signature.Schnorr.sign(
            digest: digest,
            privateKey: privateKey
        )

        return OpalBase.Hedge.OracleProofInput(
            messageHex: messageHex,
            signatureHex: signature.rawRepresentation.hexadecimalString,
            publicKeyHex: publicKey.rawRepresentation.hexadecimalString
        )
    }

    private static func makeOracleMessageHex(
        messageTimestamp: Int64,
        messageSequence: Int64,
        priceSequence: Int64,
        priceValue: Int64
    ) -> String {
        [
            messageTimestamp,
            messageSequence,
            priceSequence,
            priceValue
        ]
        .flatMap(encodeLittleEndianInteger)
        .map(makeByteHex)
        .joined()
    }

    private static func encodeLittleEndianInteger(_ value: Int64) -> [UInt8] {
        let integer = UInt32(bitPattern: Int32(value))

        return [
            UInt8(integer & 0xff),
            UInt8((integer >> 8) & 0xff),
            UInt8((integer >> 16) & 0xff),
            UInt8((integer >> 24) & 0xff)
        ]
    }

    private static func makeByteHex(_ byte: UInt8) -> String {
        let text = String(byte, radix: 16)

        return text.count == 1 ? "0" + text : text
    }
}

