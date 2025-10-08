import Foundation
import Testing
@testable import OpalBase

@Suite("Telemetry Metrics", .tags(.unit, .core))
struct TelemetryMetricsSuite {
    @Test("aggregates successes and failures", .tags(.unit, .core))
    func aggregatesSuccessesAndFailures() async {
        let sink = SelectiveFailureSink(failingEvents: ["event.failure"])
        let telemetry = Telemetry(isEnabled: true, sinks: [sink])
        
        await telemetry.record(
            name: "event.success",
            category: .analytics
        )
        await telemetry.record(
            name: "event.failure",
            category: .analytics
        )
        await telemetry.record(
            name: "event.success",
            category: .analytics
        )
        
        let snapshot = await telemetry.metricsSnapshot()
        let successKey = "analytics.event.success"
        let failureKey = "analytics.event.failure"
        
        guard let successCounters = snapshot.eventCounters[successKey] else {
            Issue.record("Missing counters for successful events")
            return
        }
        
        guard let failureCounters = snapshot.eventCounters[failureKey] else {
            Issue.record("Missing counters for failed events")
            return
        }
        
        #expect(successCounters.total == 2)
        #expect(successCounters.failures == 0)
        
        guard let successRate = successCounters.successRate else {
            Issue.record("Missing success rate for successful events")
            return
        }
        
        #expect(successRate == 1.0)
        
        #expect(failureCounters.total == 1)
        #expect(failureCounters.failures == 1)
        
        guard let failureSuccessRate = failureCounters.successRate else {
            Issue.record("Missing success rate for failed events")
            return
        }
        
        #expect(failureSuccessRate == 0.0)
    }
}

private struct SelectiveFailureSink: TelemetrySink {
    enum Error: Swift.Error {
        case forced
    }
    
    var failingEvents: Set<String>
    
    func consume(_ event: Telemetry.Event) async throws {
        if failingEvents.contains(event.name) {
            throw Error.forced
        }
    }
}
