// OpalBase+Claimable+RecoveryMaterial.swift

import Foundation

extension _OpalBase.Claimable {
    public struct RecoveryMaterial {
        public let network: OpalBase.Network.Environment
        public let spendPath: OpalBase.Claimable.SpendPath
        public let privateKeyData: Data
        public let compressedPublicKeyData: Data
        public let privateKeyHexadecimal: String
        public let privateKeyWalletImportFormat: String
        public let redeemScriptData: Data
        public let redeemScriptHexadecimal: String
        public let fundingLockingScriptData: Data
        public let fundingLockingScriptHexadecimal: String
        public let fundingScriptHashData: Data
        public let fundingScriptHashHexadecimal: String
        public let fundingTransactionHash: OpalBase.Transaction.Hash
        public let fundingTransactionIdentifier: String
        public let fundingOutputIndex: UInt32
        public let fundingValueSatoshis: UInt64
        public let expiryBlockHeight: UInt32
        public let encodedEnvelopeData: Data
        public let encodedEnvelopeHexadecimal: String

        init(
            envelope: OpalBase.Claimable.Envelope,
            spendPath: OpalBase.Claimable.SpendPath,
            privateKeyData: Data,
            compressedPublicKeyData: Data
        ) throws {
            let contract = envelope.contract
            let redeemScriptData = contract.redeemScriptData
            let fundingLockingScriptData = contract.fundingLockingScriptData
            let fundingScriptHashData = contract.fundingScriptHashData

            self.network = contract.network
            self.spendPath = spendPath
            self.privateKeyData = Data(privateKeyData)
            self.compressedPublicKeyData = Data(compressedPublicKeyData)
            self.privateKeyHexadecimal = privateKeyData.hexadecimalString
            self.privateKeyWalletImportFormat = try ClaimablePrimitiveOperation.makeWalletImportFormat(
                privateKey: privateKeyData,
                network: contract.network
            )
            self.redeemScriptData = redeemScriptData
            self.redeemScriptHexadecimal = redeemScriptData.hexadecimalString
            self.fundingLockingScriptData = fundingLockingScriptData
            self.fundingLockingScriptHexadecimal = fundingLockingScriptData.hexadecimalString
            self.fundingScriptHashData = fundingScriptHashData
            self.fundingScriptHashHexadecimal = fundingScriptHashData.hexadecimalString
            self.fundingTransactionHash = envelope.fundingTransactionHash
            self.fundingTransactionIdentifier = envelope.fundingTransactionHash.reverseOrder.hexadecimalString
            self.fundingOutputIndex = envelope.fundingOutputIndex
            self.fundingValueSatoshis = envelope.fundingValue
            self.expiryBlockHeight = contract.expiryBlockHeight
            let encodedEnvelopeData = envelope.encode()
            self.encodedEnvelopeData = encodedEnvelopeData
            self.encodedEnvelopeHexadecimal = encodedEnvelopeData.hexadecimalString
        }
    }
}

extension _OpalBase.Claimable.RecoveryMaterial: Sendable {}
extension _OpalBase.Claimable.RecoveryMaterial: Equatable {}
