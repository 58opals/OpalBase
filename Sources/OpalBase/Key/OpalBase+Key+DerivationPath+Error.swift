// OpalBase+Key+DerivationPath+Error.swift

import Foundation

extension _OpalBase.Key.DerivationPath {
    public enum Error: Swift.Error, Equatable {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}
