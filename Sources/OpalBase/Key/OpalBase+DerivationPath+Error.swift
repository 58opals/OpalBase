// OpalBase+DerivationPath+Error.swift

import Foundation

extension _OpalBase.DerivationPath {
    enum Error: Swift.Error {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}
