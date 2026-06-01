// UInt32+HardenedIndex.swift

import Foundation

extension UInt32 {
    func harden() throws -> UInt32 {
        guard self <= HardenedIndex.maxUnhardenedValue else { throw OpalBase.Key.DerivationPath.Error.indexTooLargeForHardening }
        return HardenedIndex.harden(self)
    }

    func unharden() throws -> UInt32 {
        guard HardenedIndex.isHardened(self) else { throw OpalBase.Key.DerivationPath.Error.indexTooSmallForUnhardening }
        return HardenedIndex.unharden(self)
    }
}
