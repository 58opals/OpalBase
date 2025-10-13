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
    
    @Test("guards against recording when disabled", .tags(.unit, .core))
    func guardsAgainstRecordingWhenDisabled() async {
        let sink = TelemetrySpyingSink()
        let telemetry = Telemetry(isEnabled: false, sinks: [sink])
        
        await telemetry.record(
            name: "event.disabled",
            category: .analytics
        )
        
        let consumedWhileDisabled = await sink.consumedEventCount()
        #expect(consumedWhileDisabled == 0)
        
        let disabledSnapshot = await telemetry.metricsSnapshot()
        #expect(disabledSnapshot.eventCounters.isEmpty)
        
        await telemetry.configure(isEnabled: true)
        await telemetry.record(
            name: "event.enabled",
            category: .analytics
        )
        
        let consumedAfterEnabling = await sink.consumedEventCount()
        #expect(consumedAfterEnabling == 1)
        
        let enabledSnapshot = await telemetry.metricsSnapshot()
        let enabledKey = "analytics.event.enabled"
        
        guard let enabledCounters = enabledSnapshot.eventCounters[enabledKey] else {
            Issue.record("Missing counters for enabled events")
            return
        }
        
        #expect(enabledCounters.total == 1)
        #expect(enabledCounters.failures == 0)
    }
    
    @Test("respects the disabled guard", .tags(.unit, .core))
    func ignoresEventsWhenDisabled1() async {
        let sink = TelemetrySpyingSink()
        let telemetry = Telemetry(isEnabled: false, sinks: [sink])
        let eventName = "event.guard"
        
        await telemetry.record(
            name: eventName,
            category: .analytics
        )
        
        let eventsWhileDisabled = await sink.getEvents()
        #expect(eventsWhileDisabled.isEmpty)
        
        let snapshotWhileDisabled = await telemetry.metricsSnapshot()
        #expect(snapshotWhileDisabled.eventCounters.isEmpty)
        #expect(snapshotWhileDisabled.valueAggregates.isEmpty)
        
        await telemetry.configure(isEnabled: true)
        
        await telemetry.record(
            name: eventName,
            category: .analytics
        )
        
        let eventsAfterEnabled = await sink.getEvents()
        #expect(eventsAfterEnabled.count == 1)
        
        guard let recordedEvent = eventsAfterEnabled.first else {
            Issue.record("Expected to observe event after enabling telemetry")
            return
        }
        
        #expect(recordedEvent.name == eventName)
        
        let snapshotAfterEnabled = await telemetry.metricsSnapshot()
        let analyticsKey = "analytics.\(eventName)"
        
        guard let counter = snapshotAfterEnabled.eventCounters[analyticsKey] else {
            Issue.record("Missing counters for enabled event")
            return
        }
        
        #expect(counter.total == 1)
        #expect(counter.failures == 0)
    }
    
    @Test("ignores events when disabled", .tags(.unit, .core))
    func ignoresEventsWhenDisabled2() async {
        let sink = TelemetrySpyingSink()
        let telemetry = Telemetry(isEnabled: false, sinks: [sink])
        
        await telemetry.record(
            name: "event.disabled",
            category: .analytics
        )
        
        let consumedWhileDisabled = await sink.getEvents()
        #expect(consumedWhileDisabled.isEmpty)
        
        let disabledSnapshot = await telemetry.metricsSnapshot()
        #expect(disabledSnapshot.eventCounters.isEmpty)
        
        await telemetry.configure(isEnabled: true)
        await telemetry.record(
            name: "event.enabled",
            category: .analytics
        )
        
        let consumedAfterEnabling = await sink.getEvents()
        #expect(consumedAfterEnabling.count == 1)
        #expect(consumedAfterEnabling.first?.name == "event.enabled")
        
        let enabledSnapshot = await telemetry.metricsSnapshot()
        
        guard let counters = enabledSnapshot.eventCounters["analytics.event.enabled"] else {
            Issue.record("Missing counters for enabled events")
            return
        }
        
        #expect(counters.total == 1)
        #expect(counters.failures == 0)
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

private actor TelemetrySpyingSink: TelemetrySink {
    private var consumedEvents: [Telemetry.Event] = []
    
    func consume(_ event: Telemetry.Event) async throws {
        consumedEvents.append(event)
    }
    
    func consumedEventCount() -> Int {
        consumedEvents.count
    }
    
    func getEvents() -> [Telemetry.Event] {
        consumedEvents
    }
}
