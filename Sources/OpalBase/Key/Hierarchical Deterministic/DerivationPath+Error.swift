// DerivationPath+Error.swift

import Foundation

extension DerivationPath {
    enum Error: Swift.Error {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}
