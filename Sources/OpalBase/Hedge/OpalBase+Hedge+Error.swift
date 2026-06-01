// OpalBase+Hedge+Error.swift

extension _OpalBase.Hedge {
    public enum Error: Swift.Error, Sendable, Equatable {
        case unsupportedWalletSide(Side)
        case unsupportedCounterpartySide(Side)
        case networkMismatch(expected: OpalBase.Network.Environment, actual: OpalBase.Network.Environment)
        case invalidFundingAmount(Int64)
        case invalidFundingOutputIndex(Int64)
        case invalidTransactionHash(String)
        case oraclePublicKeyMismatch(expected: String, actual: String)
        case participantLockingScriptMismatch(Side)
        case fundingOutputNotFound
        case fundingOutputAmbiguous
    }
}
