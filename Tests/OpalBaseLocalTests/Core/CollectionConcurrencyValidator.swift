// CollectionConcurrencyValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Collection concurrency", .tags(.unit))
struct CollectionConcurrencyValidator {
    enum MappingError: Swift.Error, Equatable {
        case wrapped(Int)
    }

    enum UnderlyingError: Swift.Error {
        case forced
    }

    @Test("mapConcurrently propagates cancellation without transforming it")
    func mapConcurrentlyPropagatesCancellationWithoutTransformingIt() async {
        await #expect(throws: CancellationError.self) {
            let _: [Int] = try await [1].mapConcurrently(
                transformError: { element, _ in MappingError.wrapped(element) }
            ) { _ in
                throw CancellationError()
            }
        }
    }

    @Test("mapConcurrently transforms non-cancellation errors")
    func mapConcurrentlyTransformsNonCancellationErrors() async {
        await #expect(throws: MappingError.wrapped(2)) {
            let _: [Int] = try await [2].mapConcurrently(
                transformError: { element, _ in MappingError.wrapped(element) }
            ) { _ in
                throw UnderlyingError.forced
            }
        }
    }
}
