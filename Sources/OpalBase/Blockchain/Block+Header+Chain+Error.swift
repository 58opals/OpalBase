// Block+Header+Chain+Error.swift

extension Block.Header.Chain {
    enum Error: Swift.Error {
        case invalidProofOfWork(height: UInt32)
        case doesNotConnect(height: UInt32)
    }
}
