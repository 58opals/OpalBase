// CashCodePrefixCandidateActor.swift

@testable import OpalBase

actor CashCodePrefixCandidateActor {
    private let candidates: [OpalBase.Transaction]
    private var requestCount = 0
    private var shouldSuspendNextRequest = false
    private var hasBegunSuspendedRequest = false
    private var beganContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(candidates: [OpalBase.Transaction]) {
        self.candidates = candidates
    }

    func makeCandidate(at attempt: Int) async throws -> OpalBase.Transaction {
        requestCount += 1
        if shouldSuspendNextRequest {
            shouldSuspendNextRequest = false
            hasBegunSuspendedRequest = true
            beganContinuation?.resume()
            beganContinuation = nil
            await withCheckedContinuation { continuation in
                resumeContinuation = continuation
            }
        }
        guard let candidate = candidates[
            safe: min(attempt, candidates.count - 1)
        ] else {
            throw OpalBase.ReusablePaymentAddress.Error
                .invalidPrefixGrindingCandidate
        }
        return candidate
    }

    func suspendNextRequest() {
        shouldSuspendNextRequest = true
        hasBegunSuspendedRequest = false
    }

    func waitForSuspendedRequest() async {
        guard !hasBegunSuspendedRequest else { return }
        await withCheckedContinuation { continuation in
            beganContinuation = continuation
        }
    }

    func resumeRequest() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func readRequestCount() -> Int {
        requestCount
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
