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
            self.network = envelope.contract.network
            self.spendPath = spendPath
            self.privateKeyData = privateKeyData
            self.compressedPublicKeyData = compressedPublicKeyData
            self.privateKeyHexadecimal = privateKeyData.hexadecimalString
            self.privateKeyWalletImportFormat = try makeClaimableWalletImportFormat(
                privateKey: privateKeyData,
                network: envelope.contract.network
            )
            self.redeemScriptData = envelope.contract.redeemScriptData
            self.redeemScriptHexadecimal = envelope.contract.redeemScriptData.hexadecimalString
            self.fundingLockingScriptData = envelope.contract.fundingLockingScriptData
            self.fundingLockingScriptHexadecimal = envelope.contract.fundingLockingScriptData.hexadecimalString
            self.fundingScriptHashData = envelope.contract.fundingScriptHashData
            self.fundingScriptHashHexadecimal = envelope.contract.fundingScriptHashData.hexadecimalString
            self.fundingTransactionHash = envelope.fundingTransactionHash
            self.fundingTransactionIdentifier = envelope.fundingTransactionHash.reverseOrder.hexadecimalString
            self.fundingOutputIndex = envelope.fundingOutputIndex
            self.fundingValueSatoshis = envelope.fundingValue
            self.expiryBlockHeight = envelope.contract.expiryBlockHeight
            let encodedEnvelopeData = envelope.encode()
            self.encodedEnvelopeData = encodedEnvelopeData
            self.encodedEnvelopeHexadecimal = encodedEnvelopeData.hexadecimalString
        }
    }
}

extension _OpalBase.Claimable.RecoveryMaterial: Sendable {}
extension _OpalBase.Claimable.RecoveryMaterial: Equatable {}
