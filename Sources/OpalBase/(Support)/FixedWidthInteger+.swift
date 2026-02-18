// FixedWidthInteger+.swift

import Foundation

extension FixedWidthInteger {
    @inlinable
    func addOrThrow(
        _ other: Self,
        overflowError: @autoclosure () -> Swift.Error
    ) throws -> Self {
        let (sum, overflow) = addingReportingOverflow(other)
        guard !overflow else { throw overflowError() }
        return sum
    }
    
    @inlinable
    func subtractOrThrow(
        _ other: Self,
        underflowError: @autoclosure () -> Swift.Error
    ) throws -> Self {
        let (difference, overflow) = subtractingReportingOverflow(other)
        guard !overflow else { throw underflowError() }
        return difference
    }
}
