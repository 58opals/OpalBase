// PersistencePrimitiveOperationState.swift

actor PersistencePrimitiveOperationState {
    private(set) var startedOperationCount = 0
    private(set) var completedOperationCount = 0

    func recordOperationStart() {
        startedOperationCount += 1
    }

    func recordOperationCompletion() {
        completedOperationCount += 1
    }
}
