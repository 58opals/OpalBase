// DerivationPath+Error.swift

import Foundation

extension DerivationPath {
    public enum Error: Swift.Error {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}
