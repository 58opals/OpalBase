// CashFusionFakeWrappedSession.swift

import OpalDiagnostics
#if os(macOS)
import OpalFusion
@testable import OpalBase

actor CashFusionFakeWrappedSession: OpalBase.Account.CashFusionWrappedSession {
    private let stateObserver: (any OpalFusion.Client.StateObserver)?

    private var startCount = 0
    private var stopCount = 0
    private var currentSnapshot: OpalFusion.Client.Session.Snapshot = .init()
    private var snapshotTraceIDs: [OpalDiagnostics.TraceID?] = []

    init(
        stateObserver: (any OpalFusion.Client.StateObserver)?
    ) {
        self.stateObserver = stateObserver
    }

    func start() async {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func snapshot() async -> OpalFusion.Client.Session.Snapshot {
        snapshotTraceIDs.append(OpalDiagnostics.currentTraceID)
        return currentSnapshot
    }

    func emit(snapshot: OpalFusion.Client.Session.Snapshot) async {
        currentSnapshot = snapshot
        await stateObserver?.receive(snapshot)
    }

    func readStartCount() -> Int {
        startCount
    }

    func readStopCount() -> Int {
        stopCount
    }

    func readSnapshotTraceIDs() -> [OpalDiagnostics.TraceID?] {
        snapshotTraceIDs
    }
}
#endif
