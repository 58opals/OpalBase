// MosaicOperationSuspensionProbeActor.swift

#if os(macOS)
actor MosaicOperationSuspensionProbeActor {
    private var hasSuspended = false
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        guard !hasSuspended else { return }
        hasSuspended = true
        suspendedContinuation?.resume()
        suspendedContinuation = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !hasSuspended else { return }
        await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
#endif
