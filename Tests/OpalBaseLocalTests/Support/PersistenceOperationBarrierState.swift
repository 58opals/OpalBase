// PersistenceOperationBarrierState.swift

actor PersistenceOperationBarrierState {
    private var isFirstOperationHoldingAccess = false
    private var isFirstOperationReleased = false
    private var hasSecondOperationAttemptedAccess = false
    private(set) var hasSecondOperationCompleted = false
    private var firstOperationContinuation: CheckedContinuation<Void, Never>?
    private var firstOperationWaiters: [CheckedContinuation<Void, Never>] = .init()
    private var secondOperationAttemptWaiters: [CheckedContinuation<Void, Never>] = .init()

    func holdFirstOperation() async {
        isFirstOperationHoldingAccess = true
        let waiters = firstOperationWaiters
        firstOperationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            if isFirstOperationReleased {
                continuation.resume()
            } else {
                firstOperationContinuation = continuation
            }
        }
    }

    func waitUntilFirstOperationHoldsAccess() async {
        guard !isFirstOperationHoldingAccess else {
            return
        }

        await withCheckedContinuation { continuation in
            firstOperationWaiters.append(continuation)
        }
    }

    func releaseFirstOperation() {
        isFirstOperationReleased = true
        firstOperationContinuation?.resume()
        firstOperationContinuation = nil
    }

    func recordSecondOperationAttempt() {
        hasSecondOperationAttemptedAccess = true
        let waiters = secondOperationAttemptWaiters
        secondOperationAttemptWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilSecondOperationAttemptsAccess() async {
        guard !hasSecondOperationAttemptedAccess else {
            return
        }

        await withCheckedContinuation { continuation in
            secondOperationAttemptWaiters.append(continuation)
        }
    }

    func recordSecondOperationCompletion() {
        hasSecondOperationCompleted = true
    }
}
