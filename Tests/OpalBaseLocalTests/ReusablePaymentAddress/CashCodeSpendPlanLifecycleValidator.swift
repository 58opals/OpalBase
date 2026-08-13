// CashCodeSpendPlanLifecycleValidator.swift

import Foundation
import Testing
@testable import OpalBase

private typealias CashCodePlanLifecycleError = OpalBase
    .ReusablePaymentAddress.CashCodeSpendPlan.LifecycleError

@Suite("Cash Code spend plan lifecycle", .tags(.unit, .wallet, .transaction))
struct CashCodeSpendPlanLifecycleValidator {
    @Test("one lifecycle admits one build and one terminal disposition")
    func serializeBuildAndDisposition() async throws {
        let probe = CashCodeSpendPlanLifecycleProbe()
        let lifecycle = makeLifecycle(probe: probe)
        let buildGate = CashCodeSpendPlanOperationGate()

        await expectLifecycleError(.transactionNotBuilt) {
            try await lifecycle.completeReservation()
        }

        let build = Task {
            try await lifecycle.build {
                await buildGate.suspend()
                return Self.transaction
            }
        }
        await buildGate.waitUntilSuspended()

        await expectLifecycleError(.operationInProgress) {
            _ = try await lifecycle.build { Self.transaction }
        }
        await expectLifecycleError(.operationInProgress) {
            try await lifecycle.completeReservation()
        }
        await expectLifecycleError(.operationInProgress) {
            try await lifecycle.cancelReservation()
        }

        await buildGate.resume()
        _ = try await build.value

        await expectLifecycleError(.planAlreadyUsed) {
            _ = try await lifecycle.build { Self.transaction }
        }
        try await lifecycle.completeReservation()
        #expect(await probe.completionCount == 1)
        #expect(await probe.cancellationCount == 0)
        await expectLifecycleError(.planAlreadyUsed) {
            try await lifecycle.completeReservation()
        }
        await expectLifecycleError(.planAlreadyUsed) {
            try await lifecycle.cancelReservation()
        }
    }

    @Test("build failure cancels once and disposition failure is terminal")
    func terminalizeFailuresExactlyOnce() async throws {
        let buildFailureProbe = CashCodeSpendPlanLifecycleProbe()
        let failedLifecycle = makeLifecycle(probe: buildFailureProbe)

        await #expect(throws: LifecycleProbeError.buildFailed) {
            _ = try await failedLifecycle.build {
                throw LifecycleProbeError.buildFailed
            }
        }
        #expect(await buildFailureProbe.cancellationCount == 1)
        await expectLifecycleError(.planAlreadyUsed) {
            _ = try await failedLifecycle.build { Self.transaction }
        }
        await expectLifecycleError(.planAlreadyUsed) {
            try await failedLifecycle.cancelReservation()
        }

        let dispositionFailureProbe = CashCodeSpendPlanLifecycleProbe(
            shouldFailCancellation: true
        )
        let uncertainLifecycle = makeLifecycle(
            probe: dispositionFailureProbe
        )
        await #expect(
            throws: CashCodePlanLifecycleError.reservationDispositionFailed
        ) {
            try await uncertainLifecycle.cancelReservation()
        }
        #expect(await dispositionFailureProbe.cancellationCount == 1)
        await expectLifecycleError(.planAlreadyUsed) {
            try await uncertainLifecycle.cancelReservation()
        }
    }

    @Test("task cancellation owns the final build transition and releases once")
    func cancellationAfterSuspendedBuildReleasesOnce() async {
        let probe = CashCodeSpendPlanLifecycleProbe()
        let lifecycle = makeLifecycle(probe: probe)
        let buildGate = CashCodeSpendPlanOperationGate()
        let build = Task {
            try await lifecycle.build {
                await buildGate.suspend()
                return Self.transaction
            }
        }

        await buildGate.waitUntilSuspended()
        build.cancel()
        await buildGate.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await build.value
        }
        #expect(await probe.cancellationCount == 1)
        #expect(await probe.completionCount == 0)
        await expectLifecycleError(.planAlreadyUsed) {
            _ = try await lifecycle.build { Self.transaction }
        }
        await expectLifecycleError(.planAlreadyUsed) {
            try await lifecycle.cancelReservation()
        }
    }

    @Test("terminal disposition finishes after caller cancellation")
    func terminalDispositionOutlivesCallerCancellation() async throws {
        let probe = CashCodeSpendPlanLifecycleProbe()
        let dispositionGate = CashCodeSpendPlanOperationGate()
        let lifecycle = CashCodeSpendPlanLifecycle(
            completeReservation: {},
            cancelReservation: {
                await dispositionGate.suspend()
                try Task.checkCancellation()
                try await probe.cancel()
            }
        )
        let cancellation = Task {
            try await lifecycle.cancelReservation()
        }

        await dispositionGate.waitUntilSuspended()
        cancellation.cancel()
        await dispositionGate.resume()
        try await cancellation.value

        #expect(await probe.cancellationCount == 1)
        await expectLifecycleError(.planAlreadyUsed) {
            try await lifecycle.cancelReservation()
        }
    }

    private func makeLifecycle(
        probe: CashCodeSpendPlanLifecycleProbe
    ) -> CashCodeSpendPlanLifecycle {
        CashCodeSpendPlanLifecycle(
            completeReservation: {
                await probe.complete()
            },
            cancelReservation: {
                try await probe.cancel()
            }
        )
    }

    private func expectLifecycleError(
        _ expectedError: CashCodePlanLifecycleError,
        _ operation: () async throws -> Void
    ) async {
        await #expect(throws: expectedError) {
            try await operation()
        }
    }

    private static let transaction = OpalBase.Transaction(
        version: 2,
        inputs: [],
        outputs: [],
        lockTime: 0
    )

    fileprivate enum LifecycleProbeError: Swift.Error, Equatable {
        case buildFailed
        case dispositionFailed
    }
}

private actor CashCodeSpendPlanLifecycleProbe {
    private(set) var completionCount = 0
    private(set) var cancellationCount = 0
    private let shouldFailCancellation: Bool

    init(shouldFailCancellation: Bool = false) {
        self.shouldFailCancellation = shouldFailCancellation
    }

    func complete() {
        completionCount += 1
    }

    func cancel() throws {
        cancellationCount += 1
        if shouldFailCancellation {
            throw CashCodeSpendPlanLifecycleValidator.LifecycleProbeError
                .dispositionFailed
        }
    }
}

private actor CashCodeSpendPlanOperationGate {
    private var isSuspended = false
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        suspendedContinuation?.resume()
        suspendedContinuation = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
