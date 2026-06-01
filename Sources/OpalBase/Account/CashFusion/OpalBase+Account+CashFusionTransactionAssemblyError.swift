// OpalBase+Account+CashFusionTransactionAssemblyError.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    enum CashFusionTransactionAssemblyError: Swift.Error, Equatable {
        case trailingUnsignedTransactionBytes
        case inputCountMismatch(expected: Int, actual: Int)
        case outputCountMismatch(expected: Int, actual: Int)
        case localInputMismatch
        case duplicatedLocalInput
    }
}
#endif
